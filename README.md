# Ubuntu 26.10 Post-Install Script

> **Menu-driven post-installation script with verified packages, error handling, installation checks, and automatic GNOME Shell app-folder creation**
![screenshot](screenshot.png)
---

## 📋 Table of Contents

- [🚀 Overview](#-overview)
- [✨ Features](#-features)
- [📥 Installation](#-installation)
- [🎯 Usage](#-usage)
- [🗂️ GNOME App Folders (Super Key Groups)](#️-gnome-app-folders-super-key-groups)
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
  - [Windows Software Support](#windows-software-support)
  - [Android Tools](#android-tools)
- [🔀 Bulk Options (A / B / C)](#-bulk-options-a--b--c)
- [🔧 Error Handling &amp; Installation Checks](#-error-handling--installation-checks)
- [📊 Installation Summary &amp; Logging](#-installation-summary--logging)
- [⚠️ Known Limitations](#️-known-limitations)
- [⚙️ Customization](#-customization)
- [🐛 Troubleshooting](#-troubleshooting)
- [📜 License](#-license)

---

## 🚀 Overview

This script automates the post-installation setup of **Ubuntu 26.10** by providing a menu-driven interface for installing software packages grouped by category. It is designed for developers, creatives, and power users who want to quickly set up a fully-featured development, media production, or virtualization environment.

Beyond just installing packages, after each category finishes it can also **create a real GNOME Shell app folder** for the apps it just installed, so they show up grouped together when you press the **Super key** and open the app grid — see [GNOME App Folders](#️-gnome-app-folders-super-key-groups) below.

**Key Design Principles:**

- ✅ **Verified Packages Only**: Every apt package name has been checked against the live Ubuntu 26.10 archive (`apt-cache policy`) before being added — several package names from earlier drafts (`ubuntu-studio-*`, `qemu-kvm`, `android-tools-adb`) turned out not to exist under those names and were corrected
- ✅ **Direct Downloads for Third-Party**: Non-repo tools (VS Code, Sublime Text, Ollama, Cursor, Mistral AI Vibe) use their official installers/repositories
- ✅ **Snap for Archive Gaps**: Tools with no real apt package at all (LXD, IntelliJ IDEA Community, DBeaver CE) are installed via `snap` instead of silently failing
- ✅ **Robust Error Handling**: Gracefully skips unavailable packages and continues installation
- ✅ **No Silent Duplicates**: Package lists were audited across all categories so the same tool isn't installed twice by accident (a few overlaps are intentional and documented — see [Known Limitations](#️-known-limitations) and inline comments in the script)

---

## ✨ Features

### Core Features

| Feature                       | Description                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| **Interactive Menu**          | Text-based menu with 24 categories (plus a Ubuntu Studio sub-menu)                             |
| **GNOME App-Folder Creation** | After each category, optionally groups the apps you just installed into a Super-key app folder |
| **Error Handling**             | Skips unavailable packages, continues installation                                              |
| **Pre-Install Checks**        | Verifies if packages are already installed                                                      |
| **Package Verification**      | Checks if packages exist in repositories before attempting                                      |
| **Snap Fallback**              | Installs archive-gap tools (LXD, IntelliJ, DBeaver CE) via snap with the same tracking as apt   |
| **Installation Tracking**     | Tracks installed, skipped, and failed packages per run                                          |
| **Summary Reporting**          | Shows detailed installation summary with the "S" command                                        |
| **Log Saving**                 | Saves complete logs to `/var/log/ubuntu_post_install_TIMESTAMP.log`                             |

### Statistics

- **Main Menu Categories:** 24 (plus a 6-option Ubuntu Studio sub-menu)
- **Verified APT Packages:** 200+
- **Snap-Only Tools:** 3 (LXD, IntelliJ IDEA Community, DBeaver CE)
- **Third-Party Direct-Install Tools:** ~8 (VS Code, Sublime Text, Ollama, Cursor, Mistral AI Vibe, Go, Rust/rustup, Chris Titus mybash)
- **Estimated Install Time:** 15 minutes – several hours (depending on selections; "Install EVERYTHING" is a long run)
- **Estimated Disk Space:** 5–30GB+ (depending on selections)

---

## 📥 Installation

### Prerequisites

- **Ubuntu 26.10** (recommended — the script warns and asks to continue on other versions)
- **Root access** (script must be run with `sudo`)
- **Internet connection** (for downloading packages, third-party installers, and Nerd Fonts)
- **An active GNOME desktop session** if you want app folders created (see below) — running the script over plain SSH with no desktop session will still install packages fine, it just can't create the Super-key groups
- **Minimum 10GB free disk space** (more for a full/media-heavy install)

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
chmod +x post-install.sh
sudo ./post-install.sh
```

### Menu Navigation

1. **Main Menu**: Shows all 24 categories (`0`–`24`)
2. **Sub-Menu**: Ubuntu Studio has its own sub-menu (options `1`–`6`)
3. **Bulk Options**: `A`, `B`, `C` (see [Bulk Options](#-bulk-options-a--b--c) below)
4. **`S`** — Show Installation Summary
5. **`0`** — Exit

After a single category finishes installing, you'll be asked whether to group its apps into a GNOME app folder. Bulk options (`A`/`B`/`C`) install everything in the chain but **do not** prompt for app-folder creation.

### Example Workflows

#### Install a Development Environment

```bash
sudo ./post-install.sh
# Select: 5 (Code Editors)   -> optionally create a "Code Editors" app folder
# Select: 6 (Python Development)
# Select: 7 (Web Development)
# Press 0 to exit
```

#### Install Media Production Tools

```bash
sudo ./post-install.sh
# Select: 1 (Ubuntu Studio) -> 1 (Full)
# Select: 2 (Graphics)
# Select: 3 (Video)          -> includes full codec/plugin stack + DVD support
# Select: 4 (Audio)
# Press 0 to exit
```

#### Set Up Container & VM Tooling

```bash
sudo ./post-install.sh
# Select: 16 (Container & Virtualization)
# -> installs Docker/Podman/LXC/LXD, KVM/QEMU + virt-manager/GNOME Boxes, and Cockpit
```

#### Full System Setup

```bash
sudo ./post-install.sh
# Select: C (Install EVERYTHING)
# Wait for completion (potentially a few hours)
```

---

## 🗂️ GNOME App Folders (Super Key Groups)

This is the script's headline feature beyond plain package installation: after a category installs, it can create a real **GNOME Shell app folder** (via the `org.gnome.desktop.app-folders` gsettings schema) so the apps you just installed show up grouped together when you press **Super** and open the app grid — no logout required.

**Requirements:** a live GNOME session for the target user (the script checks for `/run/user/<uid>/bus`). If none is found (e.g. running over SSH with no desktop logged in), the script warns and skips folder creation for that category — the packages themselves still install normally.

**How app resolution works.** Given a package name, the script has to figure out which real, displayable `.desktop` launcher(s) it corresponds to — this isn't always 1:1 with the apt package name, so it tries, in order:

1. **The package's own files** (`dpkg -L`) — most packages ship their own `.desktop` file directly.
2. **A full recursive dependency walk** (`apt-cache depends --recurse --important`, batched into a couple of `dpkg` calls for speed) — for meta-packages that ship no launcher of their own and depend on the real app instead. Examples: `neovim`'s launcher lives in `neovim-runtime`; `libreoffice`'s seven component apps (Writer/Calc/Impress/Draw/Base/Math/Start Center) are all separate dependencies; `emacs` depends only on an OR-alternative (`emacs-gtk`/`emacs-pgtk`/`emacs-lucid`/`emacs-nox`) and its "Emacs (Client)" launcher is two dependency levels down, in `emacs-common`.
3. **A reverse-DNS prefix guess** (`org.kde.`, `org.gnome.`, `com.obsproject.`, etc.) for cases where neither of the above resolves anything.
4. **The snap desktop directory** (`/var/lib/snapd/desktop/applications/`) for snap-only tools like DBeaver CE and IntelliJ IDEA, which `dpkg` has never heard of.

At every tier, files marked `NoDisplay=true` or `Hidden=true` are filtered out — many packages ship several `.desktop` files where only one is a real, user-facing launcher and the rest are MIME-type or print-preview helper registrations (Okular ships ~12 files and only one is real; Evince ships 2 and only one is real). The script also collects **every** real match per package rather than stopping at the first, since a meta-package can legitimately contribute several separate icons (LibreOffice, Emacs), and de-duplicates the final list in case two requested packages resolve to the same file.

If nothing resolves for a whole category, the folder is skipped with a warning rather than being silently created empty.

---

## 📦 Package Categories

Below is a breakdown of what each category actually installs, matching the current script. **All apt package names listed have been verified against the live Ubuntu 26.10 archive.**

---

### Ubuntu Studio (Media)

Official Ubuntu Studio meta-packages (note: **no hyphen** between "ubuntu" and "studio" in the real package names — `ubuntustudio-video`, not `ubuntu-studio-video`).

| Option | Package                     | Description                                             |
| ------ | ---------------------------- | -------------------------------------------------------- |
| 1      | *(runs options 2–6)*        | Full Ubuntu Studio content set (Graphics/Video/Audio/Photography/Publishing) |
| 2      | `ubuntustudio-graphics`     | Graphics applications                                    |
| 3      | `ubuntustudio-video`        | Video production tools                                   |
| 4      | `ubuntustudio-audio`        | Audio production tools                                   |
| 5      | `ubuntustudio-photography`  | Photography tools                                        |
| 6      | `ubuntustudio-publishing`   | Publishing tools                                          |

---

### Graphics &amp; Image Manipulation

**Raster/Vector Editors:** `gimp`, `inkscape`, `krita`, `darktable`, `rawtherapee`, `shotwell`, `nomacs`, `pinta`

**3D:** `blender`

**Command-line utilities:** `imagemagick`, `graphicsmagick`, `optipng`, `jpegoptim`, `pngquant`, `webp-tools`

---

### Video Creation &amp; Editing

**Editors:** `kdenlive`, `shotcut`, `pitivi`

**Encoding & Conversion:** `handbrake`, `ffmpeg`, `mkvtoolnix`, `mkvtoolnix-gui`, `yt-dlp`

**Players:** `mpv`, `vlc`

**Recording/Streaming:** `obs-studio`

**Full media codec/plugin stack** (added so real-world playback doesn't silently fail):

- `gstreamer1.0-libav`, `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good`, `gstreamer1.0-plugins-bad`, `gstreamer1.0-plugins-ugly`, `gstreamer1.0-vaapi` (hardware-accelerated decode where supported)
- `libavcodec-extra` (codec support for anything decoding through ffmpeg's libraries)
- `unrar` (many downloaded media bundles are RAR archives)
- `libdvd-pkg` — builds `libdvdcss2` (DVD decryption) from source on first install via a preseeded debconf answer, since this isn't a normal `.deb`. **Note:** whether building/using this is permitted varies by jurisdiction; it's the standard, widely-documented way Ubuntu desktops get encrypted-DVD playback working, not something forced silently — you can remove this line from `install_libdvdcss` if you don't want it.
- **Not included:** `ttf-mscorefonts-installer` (sometimes bundled via `ubuntu-restricted-extras`) — it's fonts, not a codec, and gates on an interactive EULA that defaults to declined if unattended.

---

### Audio Production

**DAWs & Editors:** `audacity`, `ardour`, `lmms`, `musescore`, `hydrogen`

**JACK Audio:** `qjackctl`, `jackd2`, `pulseaudio-module-jack`

**Plugins & Effects:** `ladspa-sdk`, `calf-plugins`

**Conversion & Tagging:** `soundconverter`, `easytag`, `flac`, `lame`, `oggenc`, `opus-tools`, `vorbis-tools`, `wavpack`, `sox`, `libsox-fmt-all`

**Mixing:** `pavucontrol` (PulseAudio volume control)

---

### Code Editors

**APT Packages:** `vim`, `neovim`, `emacs`, `nano`, `geany`, `gedit`, `kate`

**Third-Party (official repos, added and removed automatically):**

- **Visual Studio Code** — via the Microsoft apt repository
- **Sublime Text** — via the Sublime HQ apt repository

Both already-installed checks correctly mark the app as "skipped" (not silently ignored) so its icon still gets picked up for the Code Editors app folder.

---

### Python Development

`python3`, `python3-dev`, `python3-venv`, `python3-pip`, `python-is-python3`, `ipython3`, `pipx`

---

### Web Development

**Web Servers:**

- `nginx` — started normally
- `apache2` — installed with `--no-install-recommends` but deliberately **not started** (port 80 conflict with nginx); stopped if it auto-starts

**PHP baseline** (kept intentionally minimal here — just enough to serve something; deeper PHP tooling lives in [PHP Development](#php-development)): `php`, `php-cli`, `php-fpm`, `composer`

**Node.js** (shared installer with [Node.js Development](#nodejs-development) — intentionally installed from either category since it's foundational to web dev but also useful standalone):

- Added via the **NodeSource** repository, Node.js 20.x
- Global npm packages: `npm-check-updates`, `nodemon`, `pm2`, `webpack`, `webpack-cli`, `eslint`, `prettier`

**Not installed here** (moved to their own categories to avoid duplication): `memcached`, `redis-server`, `sqlite3`, `sqlitebrowser` (→ Database Tools), `ruby`/`ruby-dev` (→ Ruby Development).

---

### Java Development

**JDK/JRE & Build Tools:** `default-jdk`, `default-jre`, `gradle`, `maven`, `ant`

**Testing:** `junit4`, `testng`

**Environment:** `JAVA_HOME` is detected and written to `/etc/environment` automatically

**IDE:** `intellij-idea-community` via **snap** (`--classic`) — no Java IDE exists as a normal apt package in the Ubuntu 26.10 archive at all (checked: Eclipse, IntelliJ, NetBeans all return nothing from `apt-cache policy`), so snap is the only real distribution channel.

*(Not included: `ant-contrib`, `hamcrest`, `mockito` — not available in the Ubuntu 26.10 repositories.)*

---

### C/C++ Development

**Compilers:** `build-essential`, `gcc`, `g++`, `gfortran`, `clang`

**Build Systems:** `cmake`, `make`, `ninja-build`, `ccache`, `autoconf`, `automake`, `libtool`, `m4`, `bison`, `flex`, `gettext`, `pkg-config`

**Debugging & Profiling:** `cppcheck`, `valgrind`, `gdb`, `ltrace`, `strace`

*(`make`/`cmake`/`autoconf`/`automake`/`bison`/`flex`/`gettext`/`pkg-config` intentionally overlap with [General Development Tools](#general-development-tools) — kept as shared foundational tooling.)*

---

### Go Development

**APT Package:** `golang`

**Direct Install (if `go` isn't already on `PATH`):** downloads and installs **Go 1.22.5** from the official source to `/usr/local/go`, adds it to `PATH` via `/etc/environment`

---

### Rust Development

**APT Packages:** `rustc`, `cargo`

**Direct Install (if `rustup` isn't already present):** installs **rustup** from the official source, sets `stable` as default, adds the `rust-src` component

---

### Node.js Development

Calls the same Node.js installer used by [Web Development](#web-development) — NodeSource repository, Node.js 20.x, plus the same global npm package set. This overlap with Web Development is intentional (kept per an earlier explicit decision), not an accidental duplicate.

---

### PHP Development

**Note:** the Ondrej PHP PPA is **not yet available for Ubuntu 26.10** — this category uses the **default Ubuntu repository PHP packages only**.

`php`, `php-cli`, `php-fpm`, `php-dev`, `php-pear`, `php-mysql`, `php-pgsql`, `php-sqlite3`, `php-gd`, `php-curl`, `php-mbstring`, `php-xml`, `php-zip`, `composer`

*(The `php`/`php-cli`/`php-fpm`/`composer` baseline intentionally overlaps with Web Development — see that section's note.)*

---

### Ruby Development

`ruby`, `ruby-dev`, `ruby-bundler`

---

### Database Tools

**SQL/NoSQL Databases:** `mysql-server`, `mysql-client`, `postgresql`, `sqlite3`, `redis-server`, `redis-tools`, `memcached`

**GUI Clients:**

- `sqlitebrowser` — the only DB GUI available as a normal apt package in the Ubuntu 26.10 archive
- `dbeaver-ce` via **snap** (`--classic`) — covers MySQL/Postgres/SQLite in one tool. No MySQL Workbench, pgAdmin4, or DBeaver apt package exists in these repos at all (checked), so snap is the only real distribution channel.

---

### Container &amp; Virtualization

This category now actually covers both halves of its name — previously it only installed containers.

**Containers:**

- `docker.io`, `docker-compose`, `podman`, `lxc`
- `lxd` via **snap** (Canonical no longer ships an apt package for it)
- If Docker installs successfully: the invoking user is added to the `docker` group and the `docker` service is enabled/started

**Virtualization (KVM/QEMU):**

- `qemu-system-x86` (**not** `qemu-kvm` — that package name doesn't exist on this Ubuntu version), `qemu-utils`
- `libvirt-daemon-system`, `libvirt-clients`, `bridge-utils`
- `virtinst`, `virt-viewer`, `spice-client-gtk` — needed for virt-manager to actually create VMs and show their graphical console
- **GUI front-ends (both installed — different UX, not a duplicate):** `virt-manager` (full-featured, multi-VM) and `gnome-boxes` (GNOME's simpler one-VM-at-a-time tool)
- If `virsh` is available: the invoking user is added to the `libvirt` group and `libvirtd` is enabled/started

**Cockpit (Web GUI):**

- `cockpit`, `cockpit-machines` (VM management module), `cockpit-podman` (container management module)
- A genuinely separate, actively-maintained dashboard at `https://localhost:9090` that manages both containers and VMs — not a duplicate of virt-manager/Boxes/docker CLI. No maintained Podman Desktop or Docker Desktop apt package exists in these repos, so this is the closest apt-installable equivalent.
- `cockpit.socket` is enabled/started automatically if the install succeeds
- **Note:** Cockpit's packages ship no `.desktop` file at all (it's browser-based) — you'll see "Desktop file not found" for `cockpit`/`cockpit-machines`/`cockpit-podman` in the summary; that's expected, the same as `docker`/`podman`/`adb`.

---

### Gaming

`steam`, `lutris`, `gamemode`, `mangohud`

**32-bit Support:** adds the i386 architecture and installs `libgl1-mesa-glx:i386` for Steam

*(`obs-studio`/`mpv`/`vlc` are intentionally **not** installed here — they're not a dependency of Steam or Lutris, and [Video Creation & Editing](#video-creation--editing) already owns them.)*

---

### Office &amp; Productivity

`libreoffice`, `okular`, `evince`, `zathura`, `pandoc`

Note: `libreoffice` is a meta-package that resolves to **seven separate real apps** for app-folder purposes (Writer, Calc, Impress, Draw, Base, Math, Start Center) — see [GNOME App Folders](#️-gnome-app-folders-super-key-groups).

---

### System Utilities

**Process Monitoring:** `htop`, `iotop`, `nmon`, `sysstat`, `dstat`, `glances`

**Network Monitoring:** `nethogs`, `iftop`, `nload`, `vnstat`, `tcpdump`, `wireshark`

**System Inspection:** `lsof`, `strace`, `ltrace`, `valgrind`, `gdb`

**Shells & Terminal:** `tmux`, `screen`, `byobu`, `zsh`, `fish`, `fzf`, `ripgrep`, `tree`, `ncdu`, `rsync`, `unzip`, `bat`

> **Note:** the apt package `bat` installs its binary as `/usr/bin/batcat`, not `/usr/bin/bat` (an unrelated Debian package-name collision). Alias it yourself if you want the `bat` command to work directly.

---

### General Development Tools

`jq`, `tig`, `subversion`, `make`, `cmake`, `autoconf`, `automake`, `bison`, `flex`, `gettext`, `pkg-config`, `manpages`, `less`

*(`git` is intentionally not re-listed here — it's installed for every run as part of the base utilities in `install_base`, since the script itself needs it for the Chris Titus mybash clone step.)*

---

### AI Tools

**Third-Party Tools (direct installation):**

| Tool                | Installation Method | Description                                              |
| -------------------- | --------------------- | ----------------------------------------------------------- |
| **Ollama**          | Official install script | Local LLM runner, auto-detects GPU/CPU                  |
| **Mistral AI Vibe**  | AppImage download    | Desktop AI assistant from Mistral AI                     |
| **Claude CLI**      | `npm install -g claude` | Anthropic's CLI code assistant                           |
| **Cursor**           | `.deb` download       | AI-powered code editor                                    |

See [Known Limitations](#️-known-limitations) — none of these four currently register in the installed/skipped tracking, so the "AI Tools" app folder prompt will currently always report zero apps even on a successful install.

---

### GUI Tweaks

**Icon Sets** (via the Papirus Team PPA): `papirus-icon-theme`, `numix-icon-theme`, `breeze-icon-theme`, `adwaita-icon-theme`

**GTK Theme:** `arc-theme`

**Cursor Themes:** `dmz-cursor-theme`, `breeze-cursor-theme`

**Nerd Fonts:**

- APT packages: `fonts-firacode`, `fonts-jetbrains-mono`
- Individually downloaded from GitHub releases: FiraCode, JetBrainsMono, Hack, SourceCodePro, CascadiaCode, UbuntuMono, DejaVuSansMono
- Installed to `/usr/share/fonts/truetype/nerd-fonts/`, font cache refreshed automatically

**Chris Titus mybash:**

- Clones [christitustech/mybash](https://github.com/christitustech/mybash) into the target user's home directory
- Runs `setup.sh` **as root** (with `HOME`/`USER`/`LOGNAME` overridden to the target user) rather than via `su` — `setup.sh` calls `sudo` internally, which needs a real controlling terminal to prompt a non-root user for a password; running it as root sidesteps that entirely, since root's `sudo` never prompts
- Falls back to copying `.bashrc`, `starship.toml`, and `config.jsonc` directly if `setup.sh` fails, matching the current upstream repo layout
- Ownership is fixed back to the target user afterward; you'll need to run `source ~/.bashrc` or restart your terminal

**GUI Tools:** `gnome-tweaks`, `gnome-shell-extensions`, `gnome-themes-extra`, `nautilus`, `eog`, `file-roller`, `simple-scan`, `gnome-screenshot`, `gnome-system-monitor`, `dconf-editor`

*(`evince`/`gedit` intentionally not re-listed here — [Office & Productivity](#office--productivity) and [Code Editors](#code-editors) already own them.)*

---

### Windows Software Support

**Wine Environment:** `wine`, `winetricks`

**Wine Dependencies:** `libasound2-plugins`, `libsdl2-2.0-0`, `libfreetype6`, `libx11-6`, `libxext6`

**32-bit Support:** adds the i386 architecture automatically

**Configuration:** initializes a Wine prefix (`wineboot --init`) and installs Windows core fonts via `winetricks -q corefonts` for the target user

*(`lutris` is intentionally not installed here — it's not an apt dependency of Wine/winetricks, and [Gaming](#gaming) already owns it.)*

---

### Android Tools

`adb`, `fastboot`, `scrcpy`

- `adb`/`fastboot` are the correct package names on modern Ubuntu — the older `android-tools-adb`/`android-tools-fastboot` names from 20.04-era guides no longer exist in the archive
- `adb`/`fastboot` are CLI-only with no `.desktop` launcher — you'll see "Desktop file not found" for both, which is expected (same as `docker`/`podman`)
- `scrcpy` ([Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) — display and control your Android device) ships **two** legitimate, separate desktop launchers (a normal one and a terminal-first "console" variant), both of which get added to the app folder

---

## 🔀 Bulk Options (A / B / C)

| Option | Runs                                                                                                                                                                                            | Notes                                    |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| **A**  | Code Editors, Python, Web Development, Java, C/C++, Go, Rust, Node.js, PHP, Ruby, General Development Tools, AI Tools                                                                          | "ALL Development Tools"                  |
| **B**  | Ubuntu Studio (Full), Graphics, Video, Audio                                                                                                                                                    | "ALL Media Tools"                        |
| **C**  | Everything in A and B, plus Database Tools, Container & Virtualization, Gaming, Office & Productivity, System Utilities, GUI Tweaks, Windows Software Support, and Android Tools                | "EVERYTHING"                             |

**Important:** none of A/B/C prompt for GNOME app-folder creation — that prompt only appears after installing a single numbered category (1–24) or a Ubuntu Studio sub-menu option.

---

## 🔧 Error Handling &amp; Installation Checks

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

Snap-only tools (`lxd`, `intellij-idea-community`, `dbeaver-ce`) go through the equivalent `safe_snap_install` flow instead, checking `command -v`/`snap list` before falling back to `snap install`.

### Key Functions

| Function                            | Purpose                                                        |
| ------------------------------------ | ----------------------------------------------------------------- |
| `is_installed(pkg)`                 | Checks if a package is installed via `dpkg`                     |
| `package_exists(pkg)`               | Verifies a package exists in the apt cache                      |
| `safe_install(pkgs...)`             | Safely installs packages with the checks above                  |
| `safe_snap_install(name, [args])`   | Same tracking/checks, for snap-only tools                       |
| `batch_install(category, pkgs...)`  | Installs a batch of packages with a per-category summary line   |
| `create_menu_category(...)`         | Resolves installed packages to real `.desktop` files and creates/updates the GNOME app folder |
| `prompt_menu_category(...)`         | Asks (via `whiptail` or plain `read`) whether to create the app folder for a category |
| `log(level, message)`               | Color-coded logging (ERROR, WARNING, INFO, SUCCESS)              |

### Error Recovery

- **Failed Package Lists**: Continues installation even if some packages fail
- **Dependency Fixing**: Falls back to `apt-get install -f` where relevant
- **Retry Logic**: Allows retry for `apt-get update` and npm global package installs
- **Non-Fatal Extras**: Optional extras like `libdvd-pkg`'s DVD-decryption build failing (e.g. no network path to videolan.org) don't abort the run
- **Cleanup**: Removes temporary files and apt source entries added for third-party repos (VS Code, Sublime Text) even on failure

---

## 📊 Installation Summary &amp; Logging

### Real-Time Feedback

- 🟢 **GREEN**: Success
- 🔵 **BLUE**: Info
- 🟡 **YELLOW**: Warnings (including "Desktop file not found" for CLI-only tools — see individual category notes above for when this is expected)
- 🔴 **RED**: Errors

### Summary Screen

Press `S` at any time, or it's shown automatically after each category, to see totals, and lists of failed and skipped packages.

### Log File

```
/var/log/ubuntu_post_install_TIMESTAMP.log
```

Contains a timestamp, the running user, summary statistics, and the full installed/failed package lists for that run.

---

## ⚠️ Known Limitations

- **AI Tools tracking gap**: `install_ollama`, `install_mistral_vibe`, `install_claude_code`, and `install_cursor` never write to the installed/skipped/failed tracking arrays, even on a successful install. This means the "AI Tools" app-folder prompt currently always reports 0 apps regardless of what actually got installed (Cursor, in particular, is a real GUI app that should get an icon). Fixing this needs bookkeeping added to all four custom installers, plus the correct desktop-file name for Cursor.
- **Bulk options skip app folders**: `A`/`B`/`C` never call `prompt_menu_category`, so app folders are only offered when installing a single category at a time.
- **DVD decryption legality**: `libdvd-pkg` (in the Video category) builds `libdvdcss2` from source, which is legal in some jurisdictions and legally gray in others (this is why it's in `multiverse` rather than `main`). It's on by default; remove the `install_libdvdcss` call if you'd rather it not run.
- **`ttf-mscorefonts-installer` is deliberately excluded** from the Video category's codec stack (it's fonts, not a codec, and has its own EULA gate) — add it back yourself if you want Microsoft's core fonts.

---

## ⚙️ Customization

### Adding New Packages

```bash
batch_install "Category Name" \
    package1 \
    package2 \
    package3
```

**Important:** verify new packages exist in the Ubuntu 26.10 repos (`apt-cache policy <pkg>`) before adding them — several package-name mistakes have been caught this way already (see the inline comments throughout the script).

### Creating New Categories

1. Add an install function:
   ```bash
   install_my_category() {
       batch_install "My Category" package1 package2
   }
   ```
2. Add a menu line in `show_main_menu`: `echo " 25.  My Category"`
3. Add a case branch in `main()`:
   ```bash
   25) reset_tracking; install_my_category; display_summary; prompt_menu_category "My Category" "icon" "Comment" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
   ```
4. Optionally add the new function to the `A`/`B`/`C` bulk chains in `main()`

### Modifying Default Behavior

- Color definitions and tracking arrays are declared at the top of the script
- The `.desktop` resolution prefix guess list (for reverse-DNS-style app IDs) lives inside `create_menu_category`'s fallback tier — extend it if a new vendor's launcher isn't being found

### Disabling Categories

Comment out or remove the menu `echo` line, the `case` branch, and the function definition.

---

## 🐛 Troubleshooting

| Issue                              | Solution                                                                              |
| ------------------------------------ | ---------------------------------------------------------------------------------------- |
| **Script exits immediately**        | Run with `sudo`                                                                       |
| **Package not found**               | May not be in the Ubuntu 26.10 repos yet — check the package name or install manually |
| **Dependency errors**               | Run `sudo apt-get install -f` to fix broken dependencies                              |
| **Network errors**                  | Check your internet connection and retry                                              |
| **Disk space full**                 | Free up space (10GB+ recommended)                                                      |
| **Permission denied**               | Ensure the script is executable: `chmod +x post-install.sh`                           |
| **App folder not created**          | You need an active GNOME desktop session as the target user — check for the "No active GNOME session found" warning; running over plain SSH with nobody logged into the desktop won't work |
| **An installed app's icon is missing from its folder** | Check the summary for "Desktop file not found: `<pkg>`" — for CLI-only tools (docker, adb, cockpit, etc.) this is expected; for a real GUI app, it may need a resolver fix (see `create_menu_category` in the script) |

### Manual Installation

```bash
sudo apt-get install package-name
```

Or follow the official installation instructions for third-party tools.

### Checking Logs

```bash
# View a specific log
cat /var/log/ubuntu_post_install_*.log

# Tail the most recent
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
- Some packages have their own licenses (check individual package terms) — see especially the DVD-decryption note under [Known Limitations](#️-known-limitations)

---

## 🙏 Acknowledgments

- **Ubuntu Community**: For the excellent package repositories
- **Chris Titus Tech**: For the mybash configuration
- **Ollama**: For making local LLMs accessible
- **Mistral AI**: For Vibe and open-source AI models
- **Genymobile**: For scrcpy
- **All package maintainers**: For their hard work on the included software

---

*Last updated: August 10, 2026*
