# 🐧🎩 Linux Post-Install Scripts

> **Menu-driven post-installation scripts with verified packages, error handling, installation checks, and automatic GNOME Shell app-folder creation.**

![screenshot](screenshot.png)

This repo ships **three independent, distro-specific scripts** — pick the one that matches your machine:

- **[`post-install-ubuntu.sh`](post-install-ubuntu.sh)** — for **Ubuntu 26.04 LTS / 26.10**, built on apt/Nala.
- **[`post-install-fedora.sh`](post-install-fedora.sh)** — for **Fedora Workstation**, built on `dnf5`/RPM Fusion.
- **[`post-install-arch.sh`](post-install-arch.sh)** — for **Arch Linux and [Omarchy](https://omarchy.org)**, built on `pacman` with a `yay` AUR fallback.

They share the same Catppuccin-themed menu-driven UX, the same installed/skipped/failed tracking, and the same GNOME Shell app-folder feature — but every install path (package names, repos, drivers, codecs) is re-sourced per distro rather than being a single script with `if`-branches. None of the three scripts depends on or modifies another; run whichever matches your system.

There's also a fourth, standalone script that isn't part of that trio: **[`fedroa-setup-i3-cattpuccin.sh`](fedroa-setup-i3-cattpuccin.sh)** builds a full Catppuccin Mocha–themed **i3 tiling window manager** desktop on top of Fedora — a single-purpose rice script, not a menu-driven package browser. Run it after (or independently of) `post-install-fedora.sh`. See [i3 + Catppuccin Rice Script](#-i3--catppuccin-rice-script-fedora) below.

---

## 📋 Table of Contents

- [🐧 Ubuntu Post-Install Script](#-ubuntu-2604-lts--2610-post-install-script)
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
    - [Security Tools](#security-tools)
    - [.NET Development](#net-development)
    - [DevOps &amp; Cloud](#devops--cloud)
    - [Desktop Apps](#desktop-apps)
    - [Drivers & Extra Repos](#drivers--extra-repos)
  - [🔀 Bulk Options (A / B / C)](#-bulk-options-a--b--c)
  - [🔧 Error Handling &amp; Installation Checks](#-error-handling--installation-checks)
  - [📊 Installation Summary &amp; Logging](#-installation-summary--logging)
  - [🔒 Security Notes](#-security-notes)
  - [⚠️ Known Limitations](#️-known-limitations)
  - [⚙️ Customization](#-customization)
  - [🐛 Troubleshooting](#-troubleshooting)
- [🎩 Fedora Post-Install Script](#-fedora-post-install-script)
  - [🚀 Fedora Overview](#-fedora-overview)
  - [✨ Fedora Features](#-fedora-features)
  - [📥 Fedora Installation](#-fedora-installation)
  - [🎯 Fedora Usage](#-fedora-usage)
  - [🗂️ Fedora GNOME App Folders (Super Key Groups)](#️-fedora-gnome-app-folders-super-key-groups)
  - [📦 Fedora Package Categories](#-fedora-package-categories)
    - [Fedora: Creative Suite](#fedora-creative-suite)
    - [Fedora: Code Editors](#fedora-code-editors)
    - [Fedora: Python](#fedora-python)
    - [Fedora: Web Development](#fedora-web-development)
    - [Fedora: Java](#fedora-java)
    - [Fedora: C/C++](#fedora-cc)
    - [Fedora: Go](#fedora-go)
    - [Fedora: Rust](#fedora-rust)
    - [Fedora: Node.js](#fedora-nodejs)
    - [Fedora: PHP](#fedora-php)
    - [Fedora: Ruby](#fedora-ruby)
    - [Fedora: Databases](#fedora-databases)
    - [Fedora: Containers & VMs](#fedora-containers--vms)
    - [Fedora: Gaming](#fedora-gaming)
    - [Fedora: Office & Productivity](#fedora-office--productivity)
    - [Fedora: System Utilities](#fedora-system-utilities)
    - [Fedora: General Development Tools](#fedora-general-development-tools)
    - [Fedora: AI Tools](#fedora-ai-tools)
    - [Fedora: GUI Tweaks](#fedora-gui-tweaks)
    - [Fedora: Windows Software Support](#fedora-windows-software-support)
    - [Fedora: Android Tools](#fedora-android-tools)
    - [Fedora: Security Tools](#fedora-security-tools)
    - [Fedora: .NET](#fedora-net)
    - [Fedora: DevOps & Cloud](#fedora-devops--cloud)
    - [Fedora: Desktop Apps](#fedora-desktop-apps)
    - [Fedora: Browsers](#fedora-browsers)
    - [Fedora: Communication](#fedora-communication)
    - [Fedora: Drivers & Extra Repos](#fedora-drivers--extra-repos)
  - [🔀 Fedora Bulk Options (A / B / C)](#-fedora-bulk-options-a--b--c)
  - [🔧 Fedora Error Handling &amp; Installation Checks](#-fedora-error-handling--installation-checks)
  - [📊 Fedora Installation Summary &amp; Logging](#-fedora-installation-summary--logging)
  - [🔒 Fedora Security Notes](#-fedora-security-notes)
  - [⚠️ Fedora Known Limitations](#-fedora-known-limitations)
  - [⚙️ Fedora Customization](#-fedora-customization)
  - [🐛 Fedora Troubleshooting](#-fedora-troubleshooting)
- [🏹 Arch Linux / Omarchy Post-Install Script](#-arch-linux--omarchy-post-install-script)
  - [🚀 Arch Overview](#-arch-overview)
  - [✨ Arch Features](#-arch-features)
  - [📥 Arch Installation](#-arch-installation)
  - [🎯 Arch Usage](#-arch-usage)
  - [🗂️ Arch GNOME App Folders (Super Key Groups)](#️-arch-gnome-app-folders-super-key-groups)
  - [📦 Arch Package Categories](#-arch-package-categories)
    - [Arch: AI Tools](#arch-ai-tools)
    - [Arch: Code Editors](#arch-code-editors)
    - [Arch: Python](#arch-python)
    - [Arch: Web Development](#arch-web-development)
    - [Arch: Java](#arch-java)
    - [Arch: C/C++](#arch-cc)
    - [Arch: Go](#arch-go)
    - [Arch: Rust](#arch-rust)
    - [Arch: Node.js](#arch-nodejs)
    - [Arch: PHP](#arch-php)
    - [Arch: Ruby](#arch-ruby)
    - [Arch: .NET](#arch-net)
    - [Arch: General Dev Tools](#arch-general-dev-tools)
    - [Arch: DevOps & Cloud](#arch-devops--cloud)
    - [Arch: Database Tools](#arch-database-tools)
    - [Arch: Containers & VMs](#arch-containers--vms)
    - [Arch: Gaming](#arch-gaming)
    - [Arch: Windows Software Support](#arch-windows-software-support)
    - [Arch: Browsers](#arch-browsers)
    - [Arch: Communication](#arch-communication)
    - [Arch: Desktop Apps](#arch-desktop-apps)
    - [Arch: Creative Suite](#arch-creative-suite)
    - [Arch: Office & Productivity](#arch-office--productivity)
    - [Arch: System Utilities](#arch-system-utilities)
    - [Arch: Android Tools](#arch-android-tools)
    - [Arch: Security Tools](#arch-security-tools)
    - [Arch: Peripherals (Logitech)](#arch-peripherals-logitech)
    - [Arch: Drivers & Extra Repos](#arch-drivers--extra-repos)
    - [Arch: Snapshots & Backup](#arch-snapshots--backup)
    - [Arch: GUI Tweaks / Theming](#arch-gui-tweaks--theming)
  - [🔀 Arch Bulk Options (A / B / C)](#-arch-bulk-options-a--b--c)
  - [🔧 Arch Error Handling &amp; Installation Checks](#-arch-error-handling--installation-checks)
  - [📊 Arch Installation Summary &amp; Logging](#-arch-installation-summary--logging)
  - [🐉 Omarchy-Specific Behavior](#-omarchy-specific-behavior)
  - [🔒 Arch Security Notes](#-arch-security-notes)
  - [⚠️ Arch Known Limitations](#-arch-known-limitations)
  - [⚙️ Arch Customization](#-arch-customization)
  - [🐛 Arch Troubleshooting](#-arch-troubleshooting)
- [🎨 i3 + Catppuccin Rice Script (Fedora)](#-i3--catppuccin-rice-script-fedora)
  - [🚀 i3 Script Overview](#-i3-script-overview)
  - [📦 What Gets Installed](#-what-gets-installed)
  - [📥 i3 Script Installation & Usage](#-i3-script-installation--usage)
  - [⌨️ Keybinding Cheat Sheet](#️-keybinding-cheat-sheet)
  - [🖥️ Multi-Monitor Setup](#️-multi-monitor-setup)
  - [🛟 Rollback Safety Net](#-rollback-safety-net)
  - [⚠️ i3 Script Known Limitations & Caveats](#️-i3-script-known-limitations--caveats)
- [📜 License](#-license)
- [🙏 Acknowledgments](#-acknowledgments)

---

# 🐧 Ubuntu 26.04 LTS / 26.10 Post-Install Script

### 🚀 Overview

This script automates the post-installation setup of **Ubuntu 26.04 LTS and 26.10** by providing a menu-driven interface for installing software packages grouped by category. It is designed for developers, creatives, and power users who want to quickly set up a fully-featured development, media production, or virtualization environment.

On startup the script **detects the running release** (via `lsb_release`, falling back to `/etc/os-release`) and captures both the version and codename. Both supported releases share the same package names and codename-resolved repositories, so a single code path serves both; the few genuinely release-specific spots (e.g. PPAs that may have no build for a brand-new interim release) are handled through a small `is_lts()` / codename dispatch rather than a forked script. Running on any other version isn't blocked — the script warns and asks whether to continue.

It then **bootstraps [Nala](https://github.com/volitank/nala)** (installed with apt-get right after the first package-list update) and routes subsequent installs/updates through it for parallel downloads and cleaner output on Ubuntu's default mirrors, transparently falling back to apt-get if Nala can't be installed.

**Startup sequence** (before the menu appears), in order:

1. **Root check** — must be run with `sudo`.
2. **Version detection** — supports 26.04 LTS / 26.10; warns and asks to continue on anything else.
3. **Stale-mirror recovery** — if a previous `nala fetch` left `/etc/apt/sources.list.d/fetch.sources` behind (a common source of 404 / "is not signed" errors), offers to remove it and fall back to Ubuntu's default mirrors (prompted, default-yes, non-fatal).
4. **First package-list update** (apt-get — Nala isn't installed yet).
5. **Nala bootstrap** — installs Nala; on success all later installs/updates route through it, else apt-get.
6. **Base utilities** — `curl`, `git`, `whiptail`, `dbus-x11`, etc.
7. **Interactive menu.**

Beyond just installing packages, after each category finishes it can also **create a real GNOME Shell app folder** for the apps it just installed, so they show up grouped together when you press the **Super key** and open the app grid — see [GNOME App Folders](#️-gnome-app-folders-super-key-groups) below.

**Key Design Principles:**

- ✅ **Dual-Release Support (26.04 LTS & 26.10)**: A startup version check accepts both supported releases and stores the detected version/codename; release-specific behavior is dispatched via `is_lts()` and the resolved codename instead of maintaining two scripts. Add another release to the `SUPPORTED_VERSIONS` array to have the check accept it without prompting.
- ✅ **Nala front-end (with apt-get fallback)**: [Nala](https://github.com/volitank/nala) is installed early and used for package installs/updates (parallel downloads, cleaner output). It's a thin layer over the same libapt/dpkg, so package behavior is identical. A `pm_install`/`pm_update` abstraction routes operations through Nala when present and **falls back to apt-get** if Nala isn't available — the script works either way. Queries (`apt-cache`, `dpkg`) intentionally stay on apt, which Nala doesn't replace.
- ✅ **Verified Packages Only**: Every apt package name has been checked against the live Ubuntu 26.10 archive (`apt-cache policy`) before being added — several package names from earlier drafts (`ubuntu-studio-*`, `qemu-kvm`, `android-tools-adb`) turned out not to exist under those names and were corrected
- ✅ **Direct Downloads for Third-Party**: Non-repo tools (VS Code, Sublime Text, Ollama, Cursor, Mistral Vibe CLI) use their official installers/repositories
- ✅ **Snap for Archive Gaps**: Tools with no real apt package at all (LXD, IntelliJ IDEA Community, DBeaver CE) are installed via `snap` instead of silently failing
- ✅ **Robust Error Handling**: Gracefully skips unavailable packages and continues installation
- ✅ **No Silent Duplicates**: Package lists were audited across all categories so the same tool isn't installed twice by accident (a few overlaps are intentional and documented — see [Known Limitations](#️-known-limitations) and inline comments in the script)

---

### ✨ Features

#### Core Features

| Feature                       | Description                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| **Version Detection**         | Detects the running release at startup, supports **Ubuntu 26.04 LTS and 26.10**, warns/prompts on anything else |
| **Nala Front-End**            | Installs and uses [Nala](https://github.com/volitank/nala) for installs/updates (parallel downloads, cleaner output); transparently falls back to apt-get if unavailable |
| **Catppuccin-Themed Output**  | Menus, logs, and summary use the Catppuccin Mocha palette (truecolor), auto-disabled for non-TTY / `NO_COLOR` |
| **Interactive Menu**          | Text-based menu with 28 categories, plus Ubuntu Studio, Security, GUI Tweaks, Browsers, Communication, and Drivers & Extra Repos sub-menus |
| **GNOME App-Folder Creation** | After each category, optionally groups the apps you just installed into a Super-key app folder |
| **Terminal Font Setup**       | In GUI Tweaks, optionally sets the terminal / system monospace font to an installed Nerd Font (works on Ptyxis, GNOME Console, and gnome-terminal) |
| **Error Handling**             | Skips unavailable packages, continues installation                                              |
| **Pre-Install Checks**        | Verifies if packages are already installed                                                      |
| **Package Verification**      | Checks if packages exist in repositories before attempting                                      |
| **Snap Fallback**              | Installs archive-gap tools (LXD, IntelliJ, DBeaver CE) via snap with the same tracking as apt   |
| **Installation Tracking**     | Tracks installed, skipped, and failed packages per run                                          |
| **Summary Reporting**          | Shows detailed installation summary with the "S" command                                        |
| **Log Saving**                 | Saves complete logs to `/var/log/ubuntu_post_install_TIMESTAMP.log`                             |

#### Statistics

- **Main Menu Categories:** 28 (plus Ubuntu Studio, Security, GUI Tweaks, Browsers, Communication, and Drivers & Extra Repos sub-menus)
- **Package Front-End:** Nala (auto-installed, with transparent apt-get fallback)
- **Verified APT Packages:** 200+
- **Snap-Only Tools:** 3 (LXD, IntelliJ IDEA Community, DBeaver CE)
- **Third-Party Direct-Install Tools:** VS Code, Sublime Text, Ollama, Cursor, Mistral Vibe CLI, Claude Code, Gemini CLI, OpenCode, Go, Rust/rustup, Chris Titus mybash, Azure CLI, lazygit (via Go), LazyVim + Nordic (Neovim config)
- **Estimated Install Time:** 15 minutes – several hours (depending on selections; "Install EVERYTHING" is a long run)
- **Estimated Disk Space:** 5–30GB+ (depending on selections)

---

### 📥 Installation

#### Prerequisites

- **Ubuntu 26.04 LTS or 26.10** (the script detects the release at startup; on any other version it warns and asks whether to continue)
- **Root access** (script must be run with `sudo`)
- **Internet connection** (for downloading packages, third-party installers, and Nerd Fonts)
- **An active GNOME desktop session** if you want app folders created (see below) — running the script over plain SSH with no desktop session will still install packages fine, it just can't create the Super-key groups
- **Minimum 10GB free disk space** (more for a full/media-heavy install)

#### Quick Start

```bash
# Make the script executable
chmod +x post-install-ubuntu.sh

# Run with sudo
sudo ./post-install-ubuntu.sh
```

---

### 🎯 Usage

#### Running the Script

```bash
chmod +x post-install-ubuntu.sh
sudo ./post-install-ubuntu.sh
```

#### Menu Navigation

1. **Main Menu**: Shows all 28 categories (`0`–`28`)
2. **Sub-Menus**: Ubuntu Studio (option `1`) has a sub-menu (`1`–`6`); Security Tools (option `25`) has a sub-menu to choose Full or Defensive-only; GUI Tweaks (option `22`), Browsers (option `29`), and Communication (option `30`) each have a sub-menu to install everything in the category or pick a single item
3. **Bulk Options**: `A`, `B`, `C` (see [Bulk Options](#-bulk-options-a--b--c) below)
4. **`S`** — Show Installation Summary
5. **`0`** — Exit

After a single category finishes installing, you'll be asked whether to group its apps into a GNOME app folder. Bulk options (`A`/`B`/`C`) **auto-create** a folder per category as they go — no prompts (fitting their hands-off nature).

#### Example Workflows

##### Install a Development Environment

```bash
sudo ./post-install-ubuntu.sh
# Select: 5 (Code Editors)   -> optionally create a "Code Editors" app folder
# Select: 6 (Python Development)
# Select: 7 (Web Development)
# Press 0 to exit
```

##### Install Media Production Tools

```bash
sudo ./post-install-ubuntu.sh
# Select: 1 (Ubuntu Studio) -> 1 (Full)
# Select: 2 (Graphics)
# Select: 3 (Video)          -> includes full codec/plugin stack + DVD support
# Select: 4 (Audio)
# Press 0 to exit
```

##### Set Up Container & VM Tooling

```bash
sudo ./post-install-ubuntu.sh
# Select: 16 (Container & Virtualization)
# -> installs Docker/Podman/LXC/LXD, KVM/QEMU + virt-manager/GNOME Boxes, and Cockpit
```

##### Full System Setup

```bash
sudo ./post-install-ubuntu.sh
# Select: C (Install EVERYTHING)
# Wait for completion (potentially a few hours)
```

---

### 🗂️ GNOME App Folders (Super Key Groups)

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

### 📦 Package Categories

Below is a breakdown of what each category actually installs, matching the current script. **All apt package names listed have been verified against the live Ubuntu 26.10 archive.**

---

#### Ubuntu Studio (Media)

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

#### Graphics &amp; Image Manipulation

**Raster/Vector Editors:** `gimp`, `inkscape`, `krita`, `darktable`, `rawtherapee`, `shotwell`, `nomacs`

**3D:** `blender`

**Pinta** — apt's `pinta` was dropped from Ubuntu's repos along with Mono; installed from Flathub (`com.github.PintaProject.Pinta`) instead when the apt package isn't available, same fallback pattern as Telegram.

**Command-line utilities:** `imagemagick`, `graphicsmagick`, `optipng`, `jpegoptim`, `pngquant`, `webp-tools`

---

#### Video Creation &amp; Editing

**Editors:** `kdenlive`, `shotcut`, `pitivi`

**Encoding & Conversion:** `handbrake`, `ffmpeg`, `mkvtoolnix`, `mkvtoolnix-gui`, `yt-dlp`

**Players:** `mpv`, `vlc`

**Recording/Streaming:** `obs-studio`

**Full media codec/plugin stack** (added so real-world playback doesn't silently fail):

- `gstreamer1.0-libav`, `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good`, `gstreamer1.0-plugins-bad`, `gstreamer1.0-plugins-ugly`, `gstreamer1.0-vaapi` (hardware-accelerated decode where supported)
- `libavcodec-extra` (codec support for anything decoding through ffmpeg's libraries)
- `unrar` (many downloaded media bundles are RAR archives)
- `libdvd-pkg` — builds `libdvdcss2` (DVD decryption) from source on first install via a preseeded debconf answer, since this isn't a normal `.deb`. **Note:** whether building/using this is permitted varies by jurisdiction; it's the standard, widely-documented way Ubuntu desktops get encrypted-DVD playback working, not something forced silently — you can remove this line from `install_libdvdcss` if you don't want it.
- **`ubuntu-restricted-extras` (opt-in prompt):** extra patent-encumbered codecs (MP3/H.264 helpers) plus Microsoft core fonts. It's kept out of the default codec batch because its `ttf-mscorefonts-installer` dependency gates on an interactive **Microsoft core-fonts EULA** that would hang an unattended install. `install_restricted_extras` therefore **asks first** — the prompt states that choosing Yes accepts that EULA — and only then preseeds the answer (`debconf-set-selections`) so the install runs non-interactively. Declining is recorded as **skipped**, not failed. This prompt appears at the end of the Video category, including within the `B`/`C` bulk runs.

---

#### Audio Production

**DAWs & Editors:** `audacity`, `ardour`, `lmms`, `musescore`, `hydrogen`

**Synth:** `zynaddsubfx` — ships four separate launchers (Alsa / Jack / Jack multi-channel / Oss), all added to the app folder

**JACK Audio:** `qjackctl`, `jackd2`, `pulseaudio-module-jack`, `xjadeo` (JACK video monitor)

**Plugins & Effects:** `ladspa-sdk`, `calf-plugins`

**Conversion & Tagging:** `soundconverter`, `easytag`, `flac`, `lame`, `oggenc`, `opus-tools`, `vorbis-tools`, `wavpack`, `sox`, `libsox-fmt-all`

**Mixing:** `pavucontrol` (PulseAudio volume control)

---

#### Code Editors

**APT Packages:** `vim`, `neovim`, `emacs`, `nano`, `geany`, `gedit`, `kate`

**Third-Party (official repos, added and removed automatically):**

- **Visual Studio Code** — via the Microsoft apt repository
- **Sublime Text** — via the Sublime HQ apt repository

Both already-installed checks correctly mark the app as "skipped" (not silently ignored) so its icon still gets picked up for the Code Editors app folder.

**LazyVim + Nordic (optional prompt):** after the editors install, you're asked whether to set up [LazyVim](https://github.com/LazyVim/starter) as your Neovim config with the [Nordic](https://github.com/AlexvZyl/nordic.nvim) theme. It's a **prompted opt-in** because it **replaces `~/.config/nvim`** — any existing config is backed up to `~/.config/nvim.bak.<timestamp>` first. The clone runs as your user; plugins sync on the first `nvim` launch. The prompt also appears in the `A`/`C` bulk runs.

---

#### Python Development

`python3`, `python3-dev`, `python3-venv`, `python3-pip`, `python-is-python3`, `ipython3`, `pipx`

---

#### Web Development

**Web Servers:**

- `nginx` — started normally (owns port 80)
- `apache2` — installed with `--no-install-recommends` but deliberately **not started**. During the apache2 and PHP installs the script drops a temporary `policy-rc.d` (returning 101 for `apache2` only) so no maintainer script can auto-(re)start Apache into a port-80 collision with nginx. Without this, `apache2`/`libapache2-mod-php` postinsts fail mid-install with a systemd error.

**PHP baseline** (kept intentionally minimal here — just enough to serve something; deeper PHP tooling lives in [PHP Development](#php-development)): `php-cli`, `php-fpm`, `composer`

> The bare `php` metapackage is intentionally **not** installed. With apache2 present, `php`'s OR-dependency resolves to `libapache2-mod-php`, whose postinst restarts Apache and collides with nginx on port 80. `php-fpm` (the SAPI nginx talks to) plus `php-cli` (for composer) provide the runtime without ever pulling the Apache module.

**Node.js** (shared installer with [Node.js Development](#nodejs-development) — intentionally installed from either category since it's foundational to web dev but also useful standalone):

- Added via the **NodeSource** repository, Node.js 20.x
- Global npm packages: `npm-check-updates`, `nodemon`, `pm2`, `webpack`, `webpack-cli`, `eslint`, `prettier`

**Not installed here** (moved to their own categories to avoid duplication): `memcached`, `redis-server`, `sqlite3`, `sqlitebrowser` (→ Database Tools), `ruby`/`ruby-dev` (→ Ruby Development).

---

#### Java Development

**JDK/JRE & Build Tools:** `default-jdk`, `default-jre`, `gradle`, `maven`, `ant`

**Testing:** `junit4`, `testng`

**Environment:** `JAVA_HOME` is detected and set two ways — a bare `JAVA_HOME=…` line in `/etc/environment` (system-wide, idempotently rewritten) and a `/etc/profile.d/java-home.sh` that exports it and adds `$JAVA_HOME/bin` to `PATH` at login. **Note:** `/etc/environment` is a plain `NAME=value` file, **not** a shell script — earlier versions wrote `export JAVA_HOME=…` there, which breaks any dpkg maintainer script that reads the file (e.g. `install-info`) with `export: … bad variable name` and then fails every later package. The current code writes the correct format and the detection step also strips any malformed `export` lines a previous run left behind.

**IDE:** `intellij-idea-community` via **snap** (`--classic`) — no Java IDE exists as a normal apt package in the Ubuntu 26.10 archive at all (checked: Eclipse, IntelliJ, NetBeans all return nothing from `apt-cache policy`), so snap is the only real distribution channel.

*(Not included: `ant-contrib`, `hamcrest`, `mockito` — not available in the Ubuntu 26.10 repositories.)*

---

#### C/C++ Development

**Compilers:** `build-essential`, `gcc`, `g++`, `gfortran`, `clang`

**Build Systems:** `cmake`, `make`, `ninja-build`, `ccache`, `autoconf`, `automake`, `libtool`, `m4`, `bison`, `flex`, `gettext`, `pkg-config`

**Debugging & Profiling:** `cppcheck`, `valgrind`, `gdb`, `ltrace`, `strace`

*(`make`/`cmake`/`autoconf`/`automake`/`bison`/`flex`/`gettext`/`pkg-config` intentionally overlap with [General Development Tools](#general-development-tools) — kept as shared foundational tooling.)*

---

#### Go Development

**APT Package:** `golang`

**Direct Install (if `go` isn't already on `PATH`):** downloads and installs **Go 1.22.5** from the official source to `/usr/local/go`, and adds it to `PATH` via **`/etc/profile.d/go.sh`** (a real shell script that expands `$PATH` at login — *not* `/etc/environment`, which is a `NAME=value` pam_env file where an `export` line would break `install-info`; the step also strips any such broken line an older version left behind)

---

#### Rust Development

**APT Packages:** `rustc`, `cargo`

**Direct Install (if `rustup` isn't already present):** installs **rustup** from the official source **as the desktop user** (so the toolchain lands in *their* `~/.cargo`, not root's), sets `stable` as default, and adds the `rust-src` component. Skipped when there's no sudo-invoking user (script run as root directly).

---

#### Node.js Development

Calls the same Node.js installer used by [Web Development](#web-development) — NodeSource repository, Node.js 20.x, plus the same global npm package set. This overlap with Web Development is intentional (kept per an earlier explicit decision), not an accidental duplicate.

---

#### PHP Development

**Note:** the Ondrej PHP PPA is **not yet available for Ubuntu 26.10** — this category uses the **default Ubuntu repository PHP packages only**.

`php-cli`, `php-fpm`, `php-dev`, `php-pear`, `php-mysql`, `php-pgsql`, `php-sqlite3`, `php-gd`, `php-curl`, `php-mbstring`, `php-xml`, `php-zip`, `composer`

> As in Web Development, the bare `php` metapackage is omitted so it can't pull `libapache2-mod-php` and restart Apache into a port-80 conflict (relevant when apache2 is already installed, e.g. during an "EVERYTHING" run). The same apache-autostart guard is applied here as a safety net.

*(The `php`/`php-cli`/`php-fpm`/`composer` baseline intentionally overlaps with Web Development — see that section's note.)*

---

#### Ruby Development

`ruby`, `ruby-dev`, `ruby-bundler`

---

#### Database Tools

**SQL/NoSQL Databases:** `mysql-server`, `mysql-client`, `postgresql`, `sqlite3`, `redis-server`, `redis-tools`, `memcached`

**GUI Clients:**

- `sqlitebrowser` — the only DB GUI available as a normal apt package in the Ubuntu 26.10 archive
- `dbeaver-ce` via **snap** (`--classic`) — covers MySQL/Postgres/SQLite in one tool. No MySQL Workbench, pgAdmin4, or DBeaver apt package exists in these repos at all (checked), so snap is the only real distribution channel.

---

#### Container &amp; Virtualization

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
- If `virsh` is available: the invoking user is added to the `libvirt` group, `libvirtd` is enabled/started, and the Virtio-Win Windows-guest drivers are fetched (see below)

**Virtio-Win drivers (Windows guests):** no Debian/Ubuntu apt package or PPA exists for these, so the script downloads upstream's "latest stable" ISO directly (a static URL that's always kept current) to `/var/lib/libvirt/images/virtio-win.iso` — point a Windows VM's second CD-ROM at it during install to get the virtio network/disk/balloon drivers, instead of a crawling emulated IDE disk and no network. Skipped if that file already exists.

**Cockpit (Web GUI):**

- `cockpit`, `cockpit-machines` (VM management module), `cockpit-podman` (container management module)
- A genuinely separate, actively-maintained dashboard at `https://localhost:9090` that manages both containers and VMs — not a duplicate of virt-manager/Boxes/docker CLI. No maintained Podman Desktop or Docker Desktop apt package exists in these repos, so this is the closest apt-installable equivalent.
- `cockpit.socket` is enabled/started automatically if the install succeeds
- **Note:** Cockpit's packages ship no `.desktop` file at all (it's browser-based) — you'll see "Desktop file not found" for `cockpit`/`cockpit-machines`/`cockpit-podman` in the summary; that's expected, the same as `docker`/`podman`/`adb`.

---

#### Gaming

`steam`, `lutris`, `gamemode`, `mangohud`

**32-bit Support:** adds the i386 architecture and installs `libgl1-mesa-glx:i386` for Steam

*(`obs-studio`/`mpv`/`vlc` are intentionally **not** installed here — they're not a dependency of Steam or Lutris, and [Video Creation & Editing](#video-creation--editing) already owns them.)*

---

#### Office &amp; Productivity

`libreoffice`, `okular`, `evince`, `zathura`, `pandoc`

Note: `libreoffice` is a meta-package that resolves to **seven separate real apps** for app-folder purposes (Writer, Calc, Impress, Draw, Base, Math, Start Center) — see [GNOME App Folders](#️-gnome-app-folders-super-key-groups).

---

#### System Utilities

**Process Monitoring:** `htop`, `iotop`, `nmon`, `sysstat`, `dstat`, `glances`

**Network Monitoring:** `nethogs`, `iftop`, `nload`, `vnstat`, `tcpdump`, `wireshark`

**System Inspection:** `lsof`, `strace`, `ltrace`, `valgrind`, `gdb`

**Shells & Terminal:** `tmux`, `screen`, `byobu`, `zsh`, `fish`, `fzf`, `ripgrep`, `tree`, `ncdu`, `rsync`, `unzip`, `bat`

> **Note:** the apt package `bat` installs its binary as `/usr/bin/batcat`, not `/usr/bin/bat` (an unrelated Debian package-name collision). Alias it yourself if you want the `bat` command to work directly.

---

#### General Development Tools

`jq`, `tig`, `subversion`, `make`, `cmake`, `autoconf`, `automake`, `bison`, `flex`, `gettext`, `pkg-config`, `manpages`, `less`

*(`git` is intentionally not re-listed here — it's installed for every run as part of the base utilities in `install_base`, since the script itself needs it for the Chris Titus mybash clone step.)*

---

#### AI Tools

**Third-Party Tools (direct installation):**

| Tool                | Installation Method | Description                                              |
| -------------------- | --------------------- | ----------------------------------------------------------- |
| **Ollama**          | Official install script | Local LLM runner, auto-detects GPU/CPU                  |
| **Alpaca**           | Flathub (`com.jeffser.Alpaca`) | Native GTK4 GUI client for Ollama                |
| **Claude Code**     | Official native installer (`claude.ai/install.sh`), npm fallback | Anthropic's CLI code assistant (provides the `claude` command) |
| **Gemini CLI**       | `npm install -g @google/gemini-cli` | Google's official CLI code assistant (provides the `gemini` command) |
| **Mistral Vibe CLI** | Official installer script (`mistral.ai/vibe/install.sh`), installs the `mistral-vibe` Python package via `uv`/`pip` | Mistral's terminal coding agent (provides the `vibe` command) |
| **OpenCode**         | Official native installer (`opencode.ai/install`), npm fallback (`opencode-ai`) | Provider-agnostic terminal AI coding agent (provides the `opencode` command) |
| **Cursor**           | `.deb` download       | AI-powered code editor                                    |

All of these register in the installed/skipped/failed tracking, so they appear in the summary and are fed to the app-folder resolver. **Cursor** ships its own `cursor.desktop` and **Alpaca** exports a Flatpak launcher, so both are grouped into the AI Tools folder. **Ollama**, **Claude Code**, **Gemini CLI**, **Mistral Vibe CLI**, and **OpenCode** are command-line only (no launcher), so they're tracked but don't get a folder icon — expected, same as `docker`/`adb`.

---

#### GUI Tweaks

Option `22` has its own sub-menu so you can install everything below at once, or pick just one piece (e.g. only **Themes**) instead of the full bundle: **All GUI Tweaks**, **Icon Sets**, **Themes**, **Cursor Themes**, **Nerd Fonts**, **Chris Titus mybash**, **GUI Tools**, **GNOME Shell Extensions**. **Themes** itself opens a further sub-menu so you can pick any single theme instead of installing the full curated set.

**Icon Sets:** (creators credited in [Acknowledgments](#-acknowledgments))

- **Apt packages** (Papirus via its Team PPA; the rest are plain universe packages): `papirus-icon-theme`, `numix-icon-theme`, `numix-icon-theme-circle`, `breeze-icon-theme`, `adwaita-icon-theme`, `obsidian-icon-theme`
- **Built from source, straight to `/usr/share/icons`** (no PPA/package exists for these): [Qogir](https://github.com/vinceliuice/Qogir-icon-theme), [WhiteSur](https://github.com/vinceliuice/WhiteSur-icon-theme), [Vimix](https://github.com/vinceliuice/Vimix-icon-theme) — each cloned and run through its own `install.sh` directly as root (their destination logic is already `$UID`-aware and has no other per-user dependency, unlike the GTK themes below, so no `su`-as-desktop-user dance is needed here). Tracked via a system-wide marker file under `/var/lib/ubuntu-postinstall-themes/`.
- **Ready-made, no build step**: [Newaita](https://github.com/cbrnix/Newaita) (light + dark) — copied straight into `/usr/share/icons`.

> The Papirus PPA is added through a codename-aware helper (`add_ppa`). PPAs are keyed by codename: the 26.04 LTS almost always has a build, while a brand-new interim release (26.10) frequently has none yet — if the PPA has no build for the running codename the helper warns and continues with the distro icon packages instead of leaving a broken apt source behind.

**GTK Theme:** `arc-theme`

**Third-party GTK/Shell themes:** Beyond the apt-packaged `arc-theme`, a curated set of popular GitHub theme projects is installed straight from source, entirely **as the logged-in desktop user** (needs an active GNOME session — skipped cleanly otherwise, same as the GNOME extensions step):

- **SASS-built GTK themes** ([Graphite](https://github.com/vinceliuice/Graphite-gtk-theme), [Colloid](https://github.com/vinceliuice/Colloid-gtk-theme), [Catppuccin](https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme), [Everforest](https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme), [Gruvbox](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme), [Kanagawa](https://github.com/Fausto-Korpsvart/Kanagawa-GKT-Theme), [Material](https://github.com/Fausto-Korpsvart/Material-GTK-Themes), [Nightfox](https://github.com/Fausto-Korpsvart/Nightfox-GTK-Theme), [Osaka](https://github.com/Fausto-Korpsvart/Osaka-GTK-Theme), [Rosé Pine](https://github.com/Fausto-Korpsvart/Rose-Pine-GTK-Theme), [Tokyonight](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme)) — each is cloned and run through its own `install.sh` with `--libadwaita` (so GTK4/Libadwaita apps pick it up too), landing in `~/.themes`. `sassc` is installed first since every one of these installers self-elevates with an internal `sudo apt install sassc` when it's missing, which would otherwise hang waiting for a terminal. Idempotent via a per-theme sentinel file under `~/.cache/ubuntu-postinstall-themes/`, since (unlike an apt package) there's no single "is it installed" check for a theme.
- **Ready-made GNOME Shell themes** ([Oval](https://github.com/metro2222/ovel), [Rounded Rectangle Dark Blue](https://github.com/metro2222/rounded-rectangle-dark-blue-theme)) — no build step, just copied into `~/.local/share/themes/`.
- **[Obsidian Flow](https://github.com/JustDeax/Obsidian-flow-shell-theme)** — installed via its own Python installer (`install.py -a`, all accent colors/light/dark) rather than a folder copy, into `~/.themes`.
- **[Material GNOME](https://github.com/SakibShahariar/material-gnome-theme)** — the repo root is the theme tree itself with no installer, so it's cloned and copied straight into `~/.themes/Material-Gnome`; its GTK4/Libadwaita stylesheets are then symlinked into `~/.config/gtk-4.0` since those apps ignore `~/.themes` entirely.
- **[Lycia](https://github.com/Aevstiel/Lycia-Theme)** — its own `install.sh` is interactive, so answers are piped in: yes to the GTK4/Libadwaita files, no to the GDM login-screen theme (that step overwrites a system `gnome-shell-theme.gresource`, too invasive for an unattended installer). Needs `gtk2-engines-murrine`, `sassc`, and `gnome-themes-extra` as runtime dependencies, installed alongside it.

All of these need the **User Themes** extension (installed by the GNOME extensions step above) to actually select and apply a shell theme; GTK themes are selectable directly in `gnome-tweaks`.

**Cursor Themes:** `dmz-cursor-theme`, `breeze-cursor-theme`

**Nerd Fonts:**

- APT packages: `fonts-firacode`, `fonts-jetbrains-mono`
- Individually downloaded from GitHub releases: FiraCode, JetBrainsMono, Hack, SourceCodePro, CascadiaCode, UbuntuMono, DejaVuSansMono
- Installed to `/usr/share/fonts/truetype/nerd-fonts/`, font cache refreshed automatically

**Terminal / System Monospace Font (optional prompt):**

After Nerd Fonts install, the script offers to set the terminal font to **JetBrainsMono Nerd Font**. This is what Chris Titus mybash's `setup.sh` also attempts, but that write targets GNOME Terminal's own keys and runs as root with no D-Bus session — so on GNOME's newer default terminal (**Ptyxis**, shipped on Ubuntu 26.04+) and under `sudo` it silently does nothing (the `dbus-launch: No such file or directory` warning). The in-script option fixes that by:

- Running as the **logged-in desktop user against their live D-Bus session** (reusing the same session/bus detection the app-folder feature uses) — never as root via `dbus-launch`.
- Setting `org.gnome.desktop.interface monospace-font-name`, the authoritative lever that **GNOME Console and a default Ptyxis both follow**, as do GNOME apps and gnome-tweaks.
- Additionally pinning **Ptyxis** to "use system font" and setting **gnome-terminal**'s per-profile font when those are present — every write is guarded, so it's a safe no-op on whichever terminal/keys aren't installed.
- Skipping cleanly (with a reason) when the font isn't actually installed or there's no active desktop session (e.g. over SSH).

Takes effect immediately in open terminals — no logout. To set it manually instead, as your user (not `sudo`):

```bash
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 12'
```

> `dbus-x11` (which provides `dbus-launch`) is installed as part of the base utilities, so the noisy `dbus-launch: No such file or directory` warning from mybash's own font step is quieted on both releases.

**Chris Titus mybash:**

- Clones [christitustech/mybash](https://github.com/christitustech/mybash) into the target user's home directory
- Runs `setup.sh` **as root** (with `HOME`/`USER`/`LOGNAME` overridden to the target user) rather than via `su` — `setup.sh` calls `sudo` internally, which needs a real controlling terminal to prompt a non-root user for a password; running it as root sidesteps that entirely, since root's `sudo` never prompts
- Falls back to copying `.bashrc`, `starship.toml`, and `config.jsonc` directly if `setup.sh` fails, matching the current upstream repo layout
- Ownership is fixed back to the target user afterward; you'll need to run `source ~/.bashrc` or restart your terminal

**GUI Tools:** `gnome-tweaks`, `gnome-shell-extensions`, `gnome-themes-extra`, `nautilus`, `eog`, `file-roller`, `simple-scan`, `gnome-screenshot`, `gnome-system-monitor`, `dconf-editor`

**GNOME Shell extensions:** installed via [`gext`](https://github.com/essembeh/gnome-extensions-cli) (set up per-user with `pipx`), as the logged-in user (needs an active GNOME session — skipped cleanly otherwise). Curated set: GSConnect, Window State Manager, Bluetooth Battery Meter, Auto Move Windows, User Themes, Clipboard History, [Dash to Dock](https://extensions.gnome.org/extension/307/dash-to-dock/), [Compact Quick Settings](https://extensions.gnome.org/extension/5527/compact-quick-settings/). Best-effort — a failed extension is logged and skipped; some need a log-out/in to activate.

**Logiops (Logitech HID++ driver) — optional prompt:** builds [PixlOne/logiops](https://github.com/PixlOne/logiops) from source and enables the `logid` service. **Prompted opt-in** because it only matters for configurable Logitech mice/keyboards and pulls a build toolchain. Writes a working `/etc/logid.cfg` (MX Master 3 / MX Master — gestures, smartshift, hi-res scroll, DPI) **embedded in the script** so it works standalone; any existing config is backed up to `/etc/logid.cfg.bak.<timestamp>` first. Edit the config in `write_logid_config()` to change mappings.

*(`evince`/`gedit` intentionally not re-listed here — [Office & Productivity](#office--productivity) and [Code Editors](#code-editors) already own them.)*

---

#### Windows Software Support

**Wine Environment:** `wine`, `winetricks`, `zenity`

> The Ubuntu `winetricks` package ships as a CLI script with **no `.desktop` launcher**, so it never got a menu icon or landed in the app folder (same reason `adb`/`docker` don't). Since winetricks has a GUI when launched with no arguments, the script now **creates a `winetricks.desktop` launcher** (if the package doesn't provide one) so it appears in menus and is grouped into the Windows Software Support folder. `zenity` is installed so that GUI can draw its dialogs.

**Wine Dependencies:** `libasound2-plugins`, `libsdl2-2.0-0`, `libfreetype6`, `libx11-6`, `libxext6`

**32-bit Support:** adds the i386 architecture automatically

**Configuration:** initializes a Wine prefix (`wineboot --init`) and installs Windows core fonts via `winetricks -q corefonts` for the target user

*(`lutris` is intentionally not installed here — it's not an apt dependency of Wine/winetricks, and [Gaming](#gaming) already owns it.)*

---

#### Android Tools

`adb`, `fastboot`, `scrcpy`

- `adb`/`fastboot` are the correct package names on modern Ubuntu — the older `android-tools-adb`/`android-tools-fastboot` names from 20.04-era guides no longer exist in the archive
- `adb`/`fastboot` are CLI-only with no `.desktop` launcher — you'll see "Desktop file not found" for both, which is expected (same as `docker`/`podman`)
- `scrcpy` ([Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) — display and control your Android device) ships **two** legitimate, separate desktop launchers (a normal one and a terminal-first "console" variant), both of which get added to the app folder

---

#### Security Tools

Standard security / pentest / defensive tooling, **all from Ubuntu's own repositories** (main/universe) — intended for authorized security testing, CTFs, education, and hardening/defensive work on systems you own or are permitted to test.

Option 25 opens a **sub-menu** with two variants:

| # | Variant | Installs |
|---|---------|----------|
| 1 | **Full (pentest + defensive)** | The complete set below — scanning, web-attack, cracking, wireless, forensics/RE, hardening, firewall/VPN |
| 2 | **Defensive only** | Blue-team subset only: hardening, integrity, auditing, anti-malware, IDS/IPS, firewall, VPN, credentials — **no** offensive/dual-use tools |

**Full** — installed in themed sub-batches:

- **Network:** `nmap`, `masscan`, `netcat-openbsd`, `hping3`, `dnsutils` *(wireshark/tcpdump intentionally not repeated — [System Utilities](#system-utilities) owns them)*
- **Web app testing:** `nikto`, `sqlmap`, `dirb`, `gobuster`, `whatweb`, `wapiti`, `wfuzz`
- **Cracking & wireless:** `john`, `hashcat`, `hydra`, `aircrack-ng`, `macchanger`
- **Forensics & reverse engineering:** `radare2`, `binwalk`, `foremost`, `sleuthkit`, `steghide`, `yara`, `exiftool`
- **Hardening & anti-malware (defensive):** `lynis`, `chkrootkit`, `rkhunter`, `clamav`, `clamav-daemon`, `fail2ban`, `aide`
- **Firewall / VPN / privacy / credentials:** `gufw`, `openvpn`, `wireguard`, `proxychains4`, `torsocks`, `keepassxc`, `ettercap-graphical`

Most of these are CLI-only (no `.desktop` launcher), so they won't get folder icons — expected, same as `nmap`/`adb`. The GUI tools (`gufw`, `keepassxc`, `ettercap-graphical`) do get grouped into the Security Tools folder. Every package name is guarded by `package_exists`, so any not present on a given release is logged "Not in repos" rather than failing the batch.

**Defensive only** — a blue-team subset that deliberately **excludes** the offensive/dual-use tools above (scanners, web-attack, crackers, wireless, MITM) and adds a few defense-specific packages the full set doesn't carry:

- **Hardening & integrity:** `lynis`, `chkrootkit`, `rkhunter`, `aide`, `debsums`, `auditd`
- **Anti-malware:** `clamav`, `clamav-daemon`
- **IDS/IPS:** `fail2ban`, `suricata`
- **Firewall / VPN / credentials:** `ufw`, `gufw`, `openvpn`, `wireguard`, `keepassxc`

> The **C (Install EVERYTHING)** bulk run uses the **Full** security set.

---

#### .NET Development

Installs the **.NET SDK** from Ubuntu's own repositories. Because the exact SDK versions available drift by release, the script installs the **newest `dotnet-sdk-*` actually present** (checks for `dotnet-sdk-10.0`, then `9.0`, then `8.0`) rather than hardcoding one that may have aged out, and adds the matching `aspnetcore-runtime-*` when packaged. EF Core and other `dotnet tool` installs are per-user (`dotnet tool install -g …`) and left to you.

> If no `dotnet-sdk-*` package is found on your release, it's logged as failed with a pointer to [Microsoft's Linux install docs](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu).

---

#### DevOps &amp; Cloud

Developer/cloud tooling installed together:

- **Docker + docker-compose** (`docker.io`, `docker-compose`) — a lightweight, dedicated Docker install; adds the invoking user to the `docker` group and enables the service. *(The [Container & Virtualization](#container--virtualization) category also installs these, alongside podman/LXC/KVM/Cockpit — this is just Docker for a dev box.)*
- **Azure CLI** — via Microsoft's official install script (`curl -sL https://aka.ms/InstallAzureCLIDeb | bash`); provides the `az` command.
- **lazygit** — installed with `go install github.com/jesseduffield/lazygit@latest`. Go is installed first if missing; the build runs **as your user** (lands in `~/go/bin`) and is symlinked into `/usr/local/bin` so it's on everyone's `PATH`.

> `docker`/`az`/`lazygit` are CLI tools with no `.desktop` launcher, so this category produces no app-folder icons (expected).

---

#### Desktop Apps

Common desktop applications:

- **Spotify** — installed from Spotify's own apt repo (`repository.spotify.com`) rather than snap, so it updates through apt; migrates off a leftover snap automatically.
- **Slack** — official `slack-desktop` `.deb` installed through the active package manager (version scraped from Slack's release notes, with a pinned fallback); migrates off a leftover snap automatically.
- **Remmina** (remote-desktop client) — installed from the upstream `remmina-next` PPA when available (codename-aware via `add_ppa`, falls back to the distro package), with the RDP (`remmina-plugin-rdp`) and secret-storage (`remmina-plugin-secret`) plugins.
- **Windows App for Linux** ([mariuszkopowski/windows-app-for-linux](https://github.com/mariuszkopowski/windows-app-for-linux)) — a remote-desktop client for Windows 365 / Azure Virtual Desktop / RDP. Not on Flathub, so the latest `x86_64` Flatpak bundle is downloaded from its GitHub releases and installed into the desktop user's per-user Flatpak scope (installs Flatpak itself first if missing).
- **TeamViewer** — official vendor `.deb` downloaded and installed directly (amd64/arm64); the package registers TeamViewer's own apt repo so future updates flow through apt.
- **1Password** — installed from [1Password's official apt repo](https://support.1password.com/install-linux/) (amd64 only); also configures the documented `debsig-verify` policy for package-integrity checks.

---

#### Drivers & Extra Repos

Unlike Fedora's version of this category, there's no proprietary GPU driver here — `ubuntu-drivers`/the distro's own tooling already covers that. Just one item:

- **DisplayLink Driver** — for USB/dock-connected display adapters (DL-3xxx–DL-7xxx chipsets). Synaptics publishes a real official apt repo (confirmed by extracting their `synaptics-repository-keyring.deb`: it drops `/etc/apt/sources.list.d/synaptics.list` pointing at `https://www.synaptics.com/sites/default/files/Ubuntu`), so the script downloads and `dpkg -i`s that keyring package, runs `apt update`, then installs `displaylink-driver` normally — the same repo/package their own `displaylink-installer.sh` uses internally when it detects apt, rather than running that vendor `.run` installer directly or hand-rolling a DKMS package. Prompted opt-in — only useful with actual DisplayLink hardware. If Secure Boot is enabled, prints the `mokutil --import`/reboot-into-MOKManager commands rather than attempting to automate them.

---

### 🔀 Bulk Options (A / B / C)

| Option | Runs                                                                                                                                                                                            | Notes                                    |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| **A**  | Code Editors, Python, Web Development, Java, C/C++, Go, Rust, Node.js, PHP, Ruby, .NET, General Development Tools, AI Tools                                                                    | "ALL Development Tools" (languages; DevOps & Cloud is C only) |
| **B**  | Ubuntu Studio (Full), Graphics, Video, Audio                                                                                                                                                    | "ALL Media Tools"                        |
| **C**  | Everything in A and B, plus Database Tools, Container & Virtualization, Gaming, Office & Productivity, System Utilities, GUI Tweaks, Windows Software Support, Android Tools, Security Tools, .NET, DevOps & Cloud, and Desktop Apps | "EVERYTHING"                             |

**App folders:** A/B/C **auto-create** a GNOME app folder for each category they install (no prompts). The individual numbered categories (1–24) and the Ubuntu Studio sub-menu instead *ask* before creating each folder. Either way, folder creation needs an active GNOME session (see [GNOME App Folders](#️-gnome-app-folders-super-key-groups)); without one, each is skipped with a warning and packages still install.

---

### 🔧 Error Handling &amp; Installation Checks

#### Installation Check Flow

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

The install/update step itself runs through the `pm_install`/`pm_update` front-end abstraction — **Nala** when available, **apt-get** otherwise — so the checks above are identical regardless of back-end. Queries (`apt-cache`, `dpkg`) always use apt directly.

Snap-only tools (`lxd`, `intellij-idea-community`, `dbeaver-ce`) go through the equivalent `safe_snap_install` flow instead, checking `command -v`/`snap list` before falling back to `snap install`.

#### Key Functions

| Function                            | Purpose                                                        |
| ------------------------------------ | ----------------------------------------------------------------- |
| `is_installed(pkg)`                 | Checks if a package is installed via `dpkg`                     |
| `package_exists(pkg)`               | Verifies a package exists in the apt cache                      |
| `install_nala`                      | Bootstraps Nala after the first update; flips `PM` to `nala` on success |
| `check_stale_fetch_sources`         | Detects a leftover `nala fetch` mirror file and offers to remove it (prompted, default-yes) |
| `pm_install(pkgs...)` / `pm_update` | Package-manager front-end — routes to Nala when available, else apt-get |
| `safe_install(pkgs...)`             | Safely installs packages with the checks above (via `pm_install`) |
| `safe_snap_install(name, [args])`   | Same tracking/checks, for snap-only tools                       |
| `batch_install(category, pkgs...)`  | Installs a batch of packages with a per-category summary line   |
| `create_menu_category(...)`         | Resolves installed packages to real `.desktop` files and creates/updates the GNOME app folder |
| `prompt_menu_category(...)`         | Asks (via `whiptail` or plain `read`) whether to create the app folder for a category (individual menu entries) |
| `auto_category(name, fn)`           | Installs a category and auto-creates its folder from that category's package delta — no prompt (bulk A/B/C) |
| `check_version` / `detect_version` / `is_lts` | Detects the running release into `UBUNTU_VERSION`/`UBUNTU_CODENAME`, gates on `SUPPORTED_VERSIONS`, and exposes an LTS dispatch flag |
| `add_ppa(ppa, tag)`                 | Codename-aware PPA add that degrades gracefully when a release has no PPA build |
| `resolve_desktop_session`           | Resolves the desktop user + uid and confirms a live D-Bus session bus exists |
| `set_terminal_font` / `configure_terminal_font` | Sets (after a prompt) the terminal / system monospace font as the logged-in user |
| `log(level, message)`               | Color-coded logging (ERROR, WARNING, INFO, SUCCESS)              |

#### Error Recovery

- **Failed Package Lists**: Continues installation even if some packages fail
- **Dependency Fixing**: Falls back to `apt-get install -f` where relevant
- **Retry Logic**: Allows retry for `apt-get update` and npm global package installs
- **Non-Fatal Extras**: Optional extras like `libdvd-pkg`'s DVD-decryption build failing (e.g. no network path to videolan.org) don't abort the run
- **Cleanup**: Removes temporary files and apt source entries added for third-party repos (VS Code, Sublime Text) even on failure

---

### 📊 Installation Summary &amp; Logging

#### Real-Time Feedback

Output is themed with the **[Catppuccin](https://github.com/catppuccin/catppuccin) Mocha** palette (24-bit truecolor), assigned by semantic role. Colors **auto-disable** when output isn't a terminal or `NO_COLOR` is set, so piped/redirected output and the log file stay plain.

- 🟢 **Green** `✓`: Success
- 🔵 **Blue** `•`: Info
- 🟡 **Yellow** `▲`: Warnings (including "Desktop file not found" for CLI-only tools — see individual category notes above for when this is expected)
- 🔴 **Red** `✗`: Errors
- 🟣 **Mauve**: headings / menu keys · **Lavender**: prompts · **Peach**: bulk actions (A/B/C)

> Best viewed in a truecolor terminal (Ptyxis, GNOME Console, most modern terminals). On a legacy 8/16-color terminal the escapes degrade to the nearest supported color.

#### Summary Screen

Press `S` at any time, or it's shown automatically after each category, to see totals, and lists of failed and skipped packages.

#### Log File

```
/var/log/ubuntu_post_install_TIMESTAMP.log
```

Contains a timestamp, the running user, summary statistics, and the full installed/failed package lists for that run.

---

### 🔒 Security Notes

The script runs as **root** and installs software from a mix of Ubuntu repos and third-party sources. What that means for trust:

- **Package integrity:** apt/Nala packages are signed by Ubuntu's archive keys. Third-party **apt repos** (VS Code, Sublime) pin their GPG key with `signed-by=` and import it directly into `/usr/share/keyrings/` (no `/tmp` intermediate). **PPAs** (Papirus, Remmina) trust the Launchpad PPA owner, whose packages run maintainer scripts as root.
- **Remote install scripts run as root, trusted over HTTPS only:** NodeSource (`setup_20.x`), Ollama (`install.sh`), and Azure CLI (`InstallAzureCLIDeb`) are piped to `bash`/`sh`. These are the vendors' official install methods; integrity rests on TLS + the vendor, with no independent checksum. The **Cursor `.deb`** (`dpkg -i`) is likewise TLS-trust only. **Claude Code**, **Mistral Vibe CLI**, **OpenCode** (all `install.sh`), and rustup are installed **as your user** (via `su - $SUDO_USER`), not root.
- **Docker group = root-equivalent:** installing Docker adds your user to the `docker` group, which grants full control of the Docker socket — effectively root. This is standard and expected; know that it's a privilege boundary. (Prefer rootless Docker if you want to avoid it.)
- **Third-party desktop code:** GNOME Shell extensions (from extensions.gnome.org) run in your shell as your user; `--classic` snaps (IntelliJ, DBeaver CE) run unconfined. Both execute third-party code by design.
- **Source builds:** Logiops is compiled and `make install`ed from source in a **private `mktemp -d`** (not a predictable, reusable `/tmp` path).
- **No secrets handled:** the script never asks for or stores passwords/tokens, and menu input (a single character) can't reach a shell.

---

### ⚠️ Known Limitations

- **Bulk options auto-create app folders**: `A`/`B`/`C` create a folder per category automatically via `auto_category` (no prompt). Categories whose packages have no GUI launcher (e.g. System Utilities, Android Tools) are skipped with a "no GUI apps" notice rather than producing an empty folder.
- **DVD decryption legality**: `libdvd-pkg` (in the Video category) builds `libdvdcss2` from source, which is legal in some jurisdictions and legally gray in others (this is why it's in `multiverse` rather than `main`). It's on by default; remove the `install_libdvdcss` call if you'd rather it not run.
- **`ubuntu-restricted-extras` is opt-in** in the Video category (MP3/H.264 codec helpers + Microsoft core fonts). It prompts before installing because saying yes accepts the Microsoft core-fonts EULA; decline and it's recorded as skipped. Note the prompt also appears during the `B`/`C` bulk runs (the one interactive point in an otherwise hands-off bulk install).
- **26.10 package parity is not exhaustively verified**: package names were checked against the 26.04-era archive; 26.10 shares the same names in practice, but any package renamed or dropped in the interim release simply lands in the `FAILED` list (via the existing `package_exists` guard) rather than being pre-corrected. The version dispatch (`is_lts`/codename) is in place for such cases as they surface.

---

### ⚙️ Customization

#### Adding New Packages

```bash
batch_install "Category Name" \
    package1 \
    package2 \
    package3
```

**Important:** verify new packages exist in the Ubuntu 26.10 repos (`apt-cache policy <pkg>`) before adding them — several package-name mistakes have been caught this way already (see the inline comments throughout the script).

#### Creating New Categories

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

#### Modifying Default Behavior

- Color definitions and tracking arrays are declared at the top of the script
- The `.desktop` resolution prefix guess list (for reverse-DNS-style app IDs) lives inside `create_menu_category`'s fallback tier — extend it if a new vendor's launcher isn't being found

#### Disabling Categories

Comment out or remove the menu `echo` line, the `case` branch, and the function definition.

---

### 🐛 Troubleshooting

| Issue                              | Solution                                                                              |
| ------------------------------------ | ---------------------------------------------------------------------------------------- |
| **Script exits immediately**        | Run with `sudo`                                                                       |
| **Package not found**               | May not be in the Ubuntu 26.10 repos yet — check the package name or install manually |
| **Dependency errors**               | Run `sudo apt-get install -f` to fix broken dependencies                              |
| **Network errors**                  | Check your internet connection and retry                                              |
| **Disk space full**                 | Free up space (10GB+ recommended)                                                      |
| **Permission denied**               | Ensure the script is executable: `chmod +x post-install-ubuntu.sh`                           |
| **App folder not created**          | You need an active GNOME desktop session as the target user — check for the "No active GNOME session found" warning; running over plain SSH with nobody logged into the desktop won't work |
| **An installed app's icon is missing from its folder** | Check the summary for "Desktop file not found: `<pkg>`" — for CLI-only tools (docker, adb, cockpit, etc.) this is expected; for a real GUI app, it may need a resolver fix (see `create_menu_category` in the script) |
| **"Designed for Ubuntu 26.04/26.10, detected: …"** | You're on a release the script isn't validated against — answer `y` to continue anyway, or add your version to `SUPPORTED_VERSIONS` at the top of the script |
| **Terminal font didn't change**     | Set it as your user (not `sudo`): `gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 12'`. Confirm the font is present with `fc-list \| grep -i jetbrains`. On Ptyxis, ensure "use system font" is on (the script sets it) |
| **"unit files changed on disk, run daemon-reload"** | Benign systemd notice when a package drops a unit/binfmt file (e.g. clang). Not an error — the script runs `systemctl daemon-reload` after each batch to reconcile it. Safe to ignore if it still appears once mid-batch |
| **`install-info` fails: `export: … bad variable name`** | A previous Java **or Go** install wrote `export` lines into `/etc/environment` (invalid there). Clean them and finish configuring: `sudo sed -i '/^export /d' /etc/environment && sudo dpkg --configure -a`. Current script versions no longer write those lines (Java → `/etc/profile.d/java-home.sh`, Go → `/etc/profile.d/go.sh`) and auto-strip old ones on the next run |
| **`404 Not Found` / `is not signed` on package downloads** | A `nala fetch`-selected mirror is incomplete/stale (the script no longer selects mirrors, but a prior run leaves the chosen mirrors in `/etc/apt/sources.list.d/fetch.sources`). Restore Ubuntu's defaults: `sudo rm -f /etc/apt/sources.list.d/fetch.sources && sudo nala update` |

#### Manual Installation

```bash
sudo apt-get install package-name
```

Or follow the official installation instructions for third-party tools.

#### Checking Logs

```bash
# View a specific log
cat /var/log/ubuntu_post_install_*.log

# Tail the most recent
ls -lt /var/log/ubuntu_post_install_*.log | head -1 | awk '{print $NF}' | xargs cat
```

---

# 🎩 Fedora Post-Install Script

### 🚀 Fedora Overview

`post-install-fedora.sh` is a from-scratch Fedora Workstation port of this project — same Catppuccin-themed menu-driven UX, same installed/skipped/failed tracking, same GNOME app-folder feature as the Ubuntu script above, but every install path re-sourced for **`dnf5`** and RPM-based Fedora instead of apt/Nala. It's a separate, independent script (not a fork controlled by a flag) — run whichever file matches your distro.

On startup the script **detects the running release** by reading `/etc/os-release` directly (`ID=fedora`, `VERSION_ID`) rather than `lsb_release`, which isn't installed by default on Fedora. Running on an unsupported release isn't blocked — the script warns and asks whether to continue, same as the Ubuntu script.

It then **bootstraps RPM Fusion** (free + nonfree) and the Cisco OpenH264 repo right after the first metadata refresh — this is the Fedora equivalent of the Ubuntu script installing Nala, except here it's load-bearing rather than cosmetic: almost every proprietary codec, driver, and third-party app below assumes RPM Fusion is already enabled.

**Startup sequence** (before the menu appears), in order:

1. **Root check** — must be run with `sudo`.
2. **Version detection** — supports the current and previous Fedora release; warns and asks to continue on anything else.
3. **Metadata refresh** (`dnf makecache`).
4. **`bootstrap_repos`** — enables RPM Fusion free + nonfree, installs their AppStream metadata, enables the Cisco OpenH264 repo.
5. **Base utilities** — `curl`, `git`, `gnupg2`, `dnf5-plugins`, `dbus-x11`, etc.
6. **Interactive menu.**

Beyond just installing packages, after each category finishes it can also **create a real GNOME Shell app folder** for the apps it just installed — identical mechanism to the Ubuntu script (`org.gnome.desktop.app-folders`), just resolving `.desktop` files via `rpm -ql` instead of `dpkg -L`. See [Fedora GNOME App Folders](#️-fedora-gnome-app-folders-super-key-groups) below.

**Key Design Decisions (how this differs from a literal 1:1 port):**

- ✅ **No per-domain metapackages, so Ubuntu Studio becomes "Creative Suite"**: Fedora has nothing like `ubuntustudio-video/audio/graphics/...`. Instead, **Creative Suite** uses Fedora's own comps groups — `dnf group install audio` (Fedora Jam) and `dnf group install design-suite` — plus a hand-curated Video Editing list and small Photography/Publishing picks. See [Fedora: Creative Suite](#fedora-creative-suite).
- ✅ **"Ultramarine" → Terra, "Nobara" → nothing**: Ultramarine Linux has no repo installable on stock Fedora (it's a full OS spin); its parent project Fyra Labs' **Terra** repo is the practical substitute, scoped to its `extras` subrepo only. Nobara's own repo is **deliberately not added** — its maintainers document it as unsafe on a non-Nobara install, and its gaming-relevant packages are all natively available via RPM Fusion/Fedora anyway.
- ✅ **Flatpak minimized**: every category was individually re-researched against vendor RPM repos, RPM Fusion, and COPR before falling back to Flatpak. It's used only for Signal, Floorp, Zen Browser, Spotify, Bruno, and Alpaca — confirmed via live research to be the only real option for each.
- ✅ **Zero Snap usage**: both of the Ubuntu script's Snap-only escape hatches (IntelliJ IDEA Community, LXD) have real Fedora-native equivalents here (Flathub, Incus) — nothing in this script touches Snap.
- ✅ **New: proprietary NVIDIA driver support**: the Ubuntu script has no GPU-driver category at all. Fedora's is an explicit opt-in with build-status polling and a flagged (not faked) Secure Boot step — see [Fedora: Drivers & Extra Repos](#fedora-drivers--extra-repos).
- ✅ **Robust Error Handling**: same `package_exists`-before-`safe_install` safety net as the Ubuntu script — an unavailable package is skipped and logged, never a hard failure.

---

### ✨ Fedora Features

#### Fedora Core Features

| Feature                       | Description                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| **Version Detection**         | Detects the running release at startup via `/etc/os-release`, warns/prompts on anything unsupported |
| **dnf5 Front-End**             | Uses plain `dnf` (dnf5 is Fedora 41+'s default) — no alternate front-end to bootstrap the way the Ubuntu script bootstraps Nala |
| **Catppuccin-Themed Output**  | Same palette/menus/logging as the Ubuntu script, auto-disabled for non-TTY / `NO_COLOR`         |
| **Interactive Menu**          | Text-based menu with 28 categories, plus Creative Suite, Security, GUI Tweaks, Browsers, Communication, and Drivers & Extra Repos sub-menus |
| **GNOME App-Folder Creation** | Identical feature to the Ubuntu script, `rpm -ql`-based resolution                              |
| **RPM Fusion Bootstrap**       | Enables free + nonfree repos and Cisco OpenH264 automatically on first run                       |
| **NVIDIA Driver Support**      | Opt-in `akmod-nvidia` + CUDA install with build-status polling and Secure Boot detection (new — no Ubuntu-script equivalent) |
| **Error Handling**             | Skips unavailable packages, continues installation                                              |
| **Pre-Install Checks**        | Verifies if packages are already installed (`rpm -q`)                                            |
| **Package Verification**      | Checks if packages exist in enabled repos before attempting (`dnf info -q`)                      |
| **Zero Snap Usage**            | Every Snap-only case in the Ubuntu script has a Flathub or native dnf equivalent here            |
| **Installation Tracking**     | Tracks installed, skipped, and failed packages per run                                          |
| **Summary Reporting**          | Shows detailed installation summary with the "S" command                                        |
| **Log Saving**                 | Saves complete logs to `/var/log/fedora_post_install_TIMESTAMP.log`                             |

#### Fedora Statistics

- **Main Menu Categories:** 28 (plus Creative Suite, Security, GUI Tweaks, Browsers, Communication, and Drivers & Extra Repos sub-menus)
- **Package Front-End:** dnf5 (Fedora 41+'s default `dnf`)
- **Third-Party/Vendor Repos:** Brave, Vivaldi, Google Chrome, Microsoft Edge, LibreWolf, TeamViewer, 1Password, Cursor, Slack, VS Code, Sublime Text, Microsoft Azure CLI, Microsoft Teams (teams-for-linux) — all real vendor `dnf`/yum repos
- **RPM Fusion-Native Apps:** Steam, Discord, Telegram Desktop (better coverage than the Ubuntu script gets from apt for the latter two)
- **COPR-Sourced:** DBeaver CE (`copart/dbeaver`)
- **Flatpak-Only (confirmed no better source exists):** Signal, Floorp, Zen Browser, Spotify, Bruno, Alpaca
- **Snap-Only Tools:** 0 — zero, by design
- **Estimated Install Time:** 15 minutes – several hours (depending on selections; "EVERYTHING" is a long run)
- **Estimated Disk Space:** 5–30GB+ (depending on selections)

---

### 📥 Fedora Installation

#### Fedora Prerequisites

- **Fedora Workstation** (current or previous release — the script detects it at startup; on any other version it warns and asks whether to continue)
- **Root access** (script must be run with `sudo`)
- **Internet connection** (for downloading packages, third-party repos/installers, and Nerd Fonts)
- **An active GNOME desktop session** if you want app folders created, GNOME Shell extensions, or user-scoped GTK/icon themes installed — running over plain SSH with no desktop session still installs packages fine, it just skips those pieces
- **Minimum 10GB free disk space** (more for a full/media-heavy install)

#### Fedora Quick Start

```bash
# Make the script executable
chmod +x post-install-fedora.sh

# Run with sudo
sudo ./post-install-fedora.sh
```

---

### 🎯 Fedora Usage

#### Fedora Menu Navigation

1. **Main Menu**: Shows all 28 categories (`0`–`28`)
2. **Sub-Menus**: Creative Suite (option `1`) has a 6-item sub-menu (Full/Graphics/Video/Audio/Photography/Publishing); GUI Tweaks (option `19`), Security Tools (option `22`), Browsers (option `26`), and Communication (option `27`) each have their own sub-menu; Drivers & Extra Repos (option `28`) offers NVIDIA, Terra, and DisplayLink as separate opt-ins
3. **Bulk Options**: `A`, `B`, `C` (see [Fedora Bulk Options](#-fedora-bulk-options-a--b--c) below)
4. **`S`** — Show Installation Summary
5. **`0`** — Exit

#### Fedora Example Workflows

##### Install a Fedora Development Environment

```bash
sudo ./post-install-fedora.sh
# Select: 2 (Code Editors)   -> optionally create a "Code Editors" app folder
# Select: 3 (Python)
# Select: 4 (Web Development)
# Press 0 to exit
```

##### Install Fedora Creative Suite Tools

```bash
sudo ./post-install-fedora.sh
# Select: 1 (Creative Suite) -> 1 (Full)
# -> installs Design Suite (graphics), Video Editing, Fedora Jam (audio), Photography, Publishing
```

##### Set Up Fedora Container & VM Tooling

```bash
sudo ./post-install-fedora.sh
# Select: 13 (Containers & VMs)
# -> installs moby-engine/podman/Incus, KVM/QEMU + virt-manager/GNOME Boxes, and Cockpit
```

##### Enable NVIDIA Driver + Full System Setup

```bash
sudo ./post-install-fedora.sh
# Select: 28 (Drivers & Extra Repos) -> 1 (NVIDIA Proprietary Driver)
# Select: C (EVERYTHING)
# Wait for completion (potentially a few hours)
```

---

### 🗂️ Fedora GNOME App Folders (Super Key Groups)

Exactly the same headline feature as the Ubuntu script — see [GNOME App Folders](#️-gnome-app-folders-super-key-groups) above for the full explanation of how it works (D-Bus session detection, `.desktop` resolution tiers, `NoDisplay`/`Hidden` filtering, snap/flatpak directory scanning). The only real difference: **tier 1** of `.desktop` resolution uses `rpm -ql <pkg>` instead of `dpkg -L`, and the meta-package dependency walk (**tier 2**) uses `rpm -q --requires` instead of `apt-cache depends --recurse --important`. Flatpak-exported app resolution (for Signal, Floorp, Zen, Spotify, Bruno, Alpaca) works identically to the Ubuntu script.

---

### 📦 Fedora Package Categories

Below is a breakdown of what each Fedora category actually installs. **Package-name confidence note:** RPM Fusion/driver/codec packages, browsers, communication apps, desktop apps, Fedora Jam/Design Suite groups, Incus, and Flathub fallbacks were all individually verified against live vendor docs, packages.fedoraproject.org, and Flathub during development. The bulk of "ordinary" packages (editors, languages, system utilities) rely on standard Fedora naming conventions rather than a live re-check against a running Fedora system — the same `package_exists`-before-`safe_install` safety net means a wrong guess is logged "Not in repos" and skipped, not a hard failure.

---

#### Fedora: Creative Suite

The Ubuntu-Studio-metapackage replacement. Option `1` opens a 6-item sub-menu:

| # | Item | Installs |
|---|------|----------|
| 1 | **Full** | Everything below (Graphics + Video + Audio + Photography + Publishing) |
| 2 | **Graphics & Design** | `dnf group install design-suite` (GIMP, Inkscape, Krita, Blender, Darktable, Scribus, digiKam, Synfig, Pitivi) + `nomacs`, `flameshot`, `imagemagick`, `GraphicsMagick`, `optipng`, `jpegoptim`, `pngquant`, `libwebp-tools`; also binds Print Screen to Flameshot |
| 3 | **Video Editing** | `kdenlive`, `shotcut`, `obs-studio`, `mkvtoolnix`, `mkvtoolnix-gui`, `mpv`, `vlc`, `yt-dlp`, plus the full multimedia codec batch below |
| 4 | **Audio Production** | `dnf group install audio` (Fedora Jam: Ardour9, Audacity, Carla, Hydrogen, Guitarix, LV2/LADSPA plugin stack) + `qjackctl`, `pulseaudio-utils`, `soundconverter`, `easytag`, `pavucontrol` |
| 5 | **Photography** | `darktable`, `rawtherapee`, `digikam`, `hugin`, `gthumb` |
| 6 | **Publishing** | `scribus`, `fontforge`, `calibre` |

**Multimedia codecs** (installed as part of Video Editing, since real-world playback needs them): `ffmpeg-free` → `ffmpeg` swap, `gstreamer1-plugins-good/bad-free/bad-freeworld/ugly/ugly-free`, `gstreamer1-plugin-libav`, `openh264`, `gstreamer1-plugin-openh264`, `mozilla-openh264` — requires RPM Fusion + the Cisco OpenH264 repo, both enabled automatically on first run.

**Design Suite and Fedora Jam overlap by design**: Design Suite already includes several photography (Darktable, digiKam) and desktop-publishing-adjacent tools, so Photography/Publishing here are intentionally kept smaller/non-redundant picks rather than a from-scratch list — mirroring how Ubuntu Studio's own metapackages sometimes overlapped too.

---

#### Fedora: Code Editors

**dnf packages:** `vim-enhanced`, `neovim`, `emacs`, `nano`, `geany`, `gnome-text-editor`, `gedit`, `kate` (both `gnome-text-editor` and `gedit` are listed since which one ships depends on the exact Fedora release — GNOME replaced gedit with gnome-text-editor in GNOME 42+)

**Third-party (official vendor repos):**

- **Visual Studio Code** — Microsoft's official yum repo (`packages.microsoft.com/yumrepos/vscode`)
- **Sublime Text** — Sublime HQ's official rpm repo (`download.sublimetext.com/rpm/stable`)

**Bruno** — installed via Flathub (`com.usebruno.Bruno`); confirmed no stable rpm or COPR exists from usebruno.com.

**LazyVim + Nordic (optional prompt):** identical feature to the Ubuntu script — replaces `~/.config/nvim` (existing config backed up first), clones [LazyVim/starter](https://github.com/LazyVim/starter) + the [Nordic](https://github.com/AlexvZyl/nordic.nvim) theme.

---

#### Fedora: Python

`python3`, `python3-devel`, `python3-pip`, `python3-virtualenv`, `ipython`, `pipx`

Fedora Workstation ships `python3` by default, and there's no `python-is-python3`-style package needed — Fedora's `python3` command already *is* the system Python.

---

#### Fedora: Web Development

**Web Servers:**

- `nginx` — started normally (owns port 80)
- `httpd` (Apache) — installed for availability but not started; RPM `%post` scriptlets don't auto-start services the way Debian's do, so there's no need for the Ubuntu script's `policy-rc.d` workaround here at all

**PHP baseline:** `php-fpm`, `php-cli`, `composer`

**Node.js:** ships natively in Fedora's own repos at a current version — **no NodeSource repo needed at all**, unlike Ubuntu. `nodejs`, `npm`, plus the same global npm package set (`npm-check-updates`, `nodemon`, `pm2`, `webpack`, `webpack-cli`, `eslint`, `prettier`).

---

#### Fedora: Java

**JDK/Build Tools:** `java-latest-openjdk`, `java-latest-openjdk-devel`, `gradle`, `maven`, `ant`, `junit`

**IDE:** IntelliJ IDEA Community via **Flathub** (`com.jetbrains.IntelliJ-IDEA-Community`) — a genuine dedicated app distinct from JetBrains Toolbox, confirmed as the real replacement for the Ubuntu script's Snap install (no Fedora/RPM Fusion package exists).

---

#### Fedora: C/C++

`gcc`, `gcc-c++`, `gcc-gfortran`, `clang`, `cmake`, `make`, `ninja-build`, `ccache`, `autoconf`, `automake`, `libtool`, `m4`, `bison`, `flex`, `gettext`, `pkgconf-pkg-config`, `cppcheck`, `valgrind`, `gdb`, `ltrace`, `strace`

---

#### Fedora: Go

**dnf package:** `golang` (installed if present in repos)

**Direct install fallback** (if `golang` isn't in repos and `go` isn't already on `PATH`): downloads Go 1.22.5 from the official source to `/usr/local/go`, symlinked into `/usr/local/bin`.

---

#### Fedora: Rust

**Primary:** installs **rustup** from the official source **as the desktop user** (same as the Ubuntu script) so the toolchain lands in *their* `~/.cargo`, not root's.

**Fallback:** distro `rust`/`cargo` packages if rustup fails or there's no sudo-invoking user.

---

#### Fedora: Node.js

Calls the same Node.js installer used by [Fedora: Web Development](#fedora-web-development) — Fedora's native `nodejs`/`npm` packages, no NodeSource repo, plus the same global npm set.

---

#### Fedora: PHP

`php-cli`, `php-fpm`, `php-devel`, `php-pear`, `php-mysqlnd`, `php-pgsql`, `php-pdo`, `php-gd`, `php-curl`, `php-mbstring`, `php-xml`, `php-zip`, `composer`

---

#### Fedora: Ruby

`ruby`, `ruby-devel`, `rubygem-bundler`

---

#### Fedora: Databases

**SQL/NoSQL:** `mariadb-server`, `mariadb` (Fedora's own repos ship MariaDB, not a plain `mysql-server` — Oracle's actual MySQL is a separate `community-mysql-server` package), `sqlite`, `sqlitebrowser`, `memcached`

**Valkey (Redis-compatible):** `valkey` — Fedora dropped the `redis` package starting Fedora 40 after Redis's license change, in favor of the Linux Foundation's redis-protocol-compatible fork. This is the current Fedora path, not a downgrade.

**PostgreSQL:** `postgresql-server`, `postgresql` — with an explicit `postgresql-setup --initdb` step run automatically if the database cluster doesn't exist yet. Unlike Debian's `postgresql-common`, RPM's `postgresql-server` package does **not** auto-initialize on install.

**GUI Client:** DBeaver CE via **COPR** (`copart/dbeaver`) — no vendor rpm repo exists (dbeaver.io only ships a Debian apt repo, a standalone rpm, and Snap/Flathub, which DBeaver Corporation itself doesn't support).

---

#### Fedora: Containers & VMs

**Containers:**

- `moby-engine` (Fedora's own Docker-compatible build), `docker-compose`, `podman` — mirrors the Ubuntu script's own existing preference for the distro package over Docker Inc.'s official repo, for consistency
- If moby-engine installs successfully: the invoking user is added to the `docker` group and the service is enabled/started
- `incus` — natively packaged in Fedora since Fedora 41, the community-maintained fork that replaces the Ubuntu script's Snap-only `lxd`

**Virtualization (KVM/QEMU):** `qemu-kvm`, `libvirt`, `virt-install`, `virt-manager`, `virt-viewer`, `gnome-boxes`, `cockpit`, `cockpit-machines`, `cockpit-podman`. If libvirt installs successfully: the invoking user is added to the `libvirt` group, `libvirtd` is enabled/started, and the Virtio-Win Windows-guest drivers are installed.

**Virtio-Win drivers (Windows guests):** Fedora doesn't carry these Windows driver RPMs in its own repos, so the script adds the upstream-maintained [virtio-win repo](https://fedorapeople.org/groups/virt/virtio-win/repo/) (via `dnf config-manager addrepo --from-repofile=...`) and installs the `virtio-win` package, then symlinks its ISO from `/usr/share/virtio-win/virtio-win.iso` into `/var/lib/libvirt/images/virtio-win.iso` for easy pickup when creating a VM. If the repo or package install doesn't go through, it falls back to downloading upstream's "latest stable" ISO directly to the same path. Skipped if that file already exists.

> Fedora handles 32-bit/multilib packages natively via `.i686` builds — there's no Ubuntu-style "add the i386 architecture" step needed anywhere in this script.

---

#### Fedora: Gaming

`steam` (from RPM Fusion nonfree — proprietary EULA), `lutris`, `gamemode`, `mangohud` (all three from Fedora's **own** repos, no RPM Fusion needed).

RPM Fusion's native Steam package is fully functional for Proton/Steam Play and controller support (pulls in `steam-devices` udev rules + system Vulkan/Mesa libs that Lutris/MangoHud also share) — the Fedora community's own recommended default over the Flatpak version.

---

#### Fedora: Office & Productivity

`libreoffice`, `okular`, `evince`, `gnome-papers`, `zathura`, `pandoc`

Both `evince` and `gnome-papers` are listed since which one ships depends on the exact Fedora release — GNOME is transitioning from Evince to Papers.

---

#### Fedora: System Utilities

**Process Monitoring:** `htop`, `iotop`, `sysstat`, `glances`

**Network Monitoring:** `nethogs`, `iftop`, `nload`, `vnstat`, `tcpdump`, `wireshark`

**System Inspection:** `lsof`, `strace`, `ltrace`, `valgrind`, `gdb`

**Shells & Terminal:** `tmux`, `screen`, `zsh`, `fish`, `fzf`, `ripgrep`, `tree`, `ncdu`, `rsync`, `unzip`, `bat`

> Unlike Ubuntu's `bat` package (which installs as `/usr/bin/batcat` due to a Debian name collision), Fedora's `bat` package installs straight to `/usr/bin/bat` — no alias needed.

---

#### Fedora: General Development Tools

`jq`, `tig`, `subversion`, `make`, `cmake`, `autoconf`, `automake`, `bison`, `flex`, `gettext`, `pkgconf-pkg-config`, `man-db`, `man-pages`, `less`, plus Bruno (Flathub, see [Fedora: Code Editors](#fedora-code-editors))

---

#### Fedora: AI Tools

Same tool set as the Ubuntu script — almost entirely package-manager-agnostic (vendor curl-installer scripts, npm globals, Flathub), ported near-verbatim:

| Tool | Installation Method |
|------|---------------------|
| **Ollama** | Official install script |
| **Alpaca** | Flathub (`com.jeffser.Alpaca`) |
| **Claude Code** | Official native installer, npm fallback |
| **Gemini CLI** | `npm install -g @google/gemini-cli` |
| **Mistral Vibe CLI** | Official installer script |
| **OpenCode** | Official native installer, npm fallback |
| **Cursor** | Official yum repo (`downloads.cursor.com/yumrepo`) — real vendor repo as of ~2025, simpler than the Ubuntu script's `.deb`/AppImage download-API dance |

---

#### Fedora: GUI Tweaks

Option `19` has its own sub-menu: **All GUI Tweaks**, **Icon Sets**, **Themes**, **Cursor Themes**, **Nerd Fonts**, **Chris Titus mybash**, **GUI Tools**, **GNOME Shell Extensions** — same shape as the Ubuntu script's. **Themes** opens a further sub-menu so you can pick a single theme instead of installing all of them.

**Icon Sets:**

- **dnf packages** (all ship directly in Fedora's own repos — no PPA equivalent needed for any of them): `papirus-icon-theme`, `numix-icon-theme`, `numix-icon-theme-circle`, `breeze-icon-theme`, `adwaita-icon-theme`, `obsidian-icon-theme`
- **Built from source, straight to `/usr/share/icons`**: [Qogir](https://github.com/vinceliuice/Qogir-icon-theme), [WhiteSur](https://github.com/vinceliuice/WhiteSur-icon-theme), [Vimix](https://github.com/vinceliuice/Vimix-icon-theme) — same mechanism as the Ubuntu script (their destination logic is `$UID`-aware, so this runs directly as root, no `su`-as-desktop-user needed)
- **Ready-made, no build step**: [Newaita](https://github.com/cbrnix/Newaita) (light + dark)

**GTK Themes:** [Nordic](https://github.com/EliverLara/Nordic) and [Colloid](https://github.com/vinceliuice/Colloid-gtk-theme) (Colloid cloned + `install.sh`, same mechanism as the Qogir/WhiteSur/Vimix icon themes above but landing in `~/.themes`), [Material GNOME](https://github.com/SakibShahariar/material-gnome-theme) (no installer — cloned straight into `~/.themes/Material-Gnome` with its GTK4/Libadwaita stylesheets symlinked into `~/.config/gtk-4.0`), and [Lycia](https://github.com/Aevstiel/Lycia-Theme) (its interactive `install.sh` is fed "yes" to the GTK4/Libadwaita files and "no" to the GDM login-screen theme — that step overwrites a system `gnome-shell-theme.gresource`, too invasive for an unattended installer; needs `gtk-murrine-engine`, `sassc`, and `gnome-themes-extra` as runtime deps).

**GNOME Shell Extensions:** same curated set as the Ubuntu script (GSConnect, Window State Manager, Bluetooth Battery Meter, Auto Move Windows, User Themes, Clipboard History, Dash to Dock, Compact Quick Settings), installed via `gext`/pipx identically.

**Chris Titus mybash:** same clone + `setup.sh` flow; upstream's `setup.sh` itself detects `dnf` and calls `sudo dnf install ...` internally rather than apt.

---

#### Fedora: Windows Software Support

`wine`, `winetricks`, `zenity` — same hand-written `winetricks.desktop` launcher as the Ubuntu script (Fedora's winetricks package also ships no `.desktop` file of its own).

---

#### Fedora: Android Tools

`android-tools` (Fedora bundles adb+fastboot into one package, unlike Ubuntu's separate `adb`/`fastboot`), `scrcpy`

---

#### Fedora: Security Tools

Option `22` opens the same two-variant sub-menu as the Ubuntu script (Full / Defensive-only). **Caveat flagged more prominently here than other categories**: several classic pentest tools have historically been thin or absent in Fedora's own repos (no PPA-equivalent to pull them from) — expect more "Not in repos" skips here than elsewhere. Real GUI tools (`firewall-config`, `keepassxc`) get folder icons.

**Firewall:** uses `firewalld` + `firewall-config` — Fedora's own default firewall manager, replacing the Ubuntu script's `ufw`/`gufw` pairing (there's no Fedora equivalent of `ufw`; firewalld already fills that role).

Package sets otherwise mirror the Ubuntu script's Full/Defensive split closely: network scanning (`nmap`, `masscan`, `nmap-ncat`, `hping3`, `bind-utils`), web testing (`nikto`, `sqlmap`, `gobuster`, `whatweb`, `wfuzz`), cracking/wireless (`john`, `hashcat`, `hydra`, `aircrack-ng`, `macchanger`), forensics/RE (`radare2`, `binwalk`, `sleuthkit`, `steghide`, `yara`, `perl-Image-ExifTool`), hardening (`lynis`, `chkrootkit`, `rkhunter`, `clamav`, `clamav-update`, `fail2ban`, `aide`), and — Defensive-only adds `audit`, `suricata`.

---

#### Fedora: .NET

`dotnet-sdk-9.0`, `dotnet-sdk-8.0`, `aspnetcore-runtime-9.0` — ships **natively in Fedora's own repos**, no Microsoft repo needed at all (mixing Microsoft's repo with Fedora's own dotnet packages is explicitly discouraged upstream). Simpler than the Ubuntu script's `packages.microsoft.com` dance.

---

#### Fedora: DevOps & Cloud

- **Docker (standalone)** — `moby-engine` + `docker-compose`, same distro-native choice as [Fedora: Containers & VMs](#fedora-containers--vms)
- **Azure CLI** — Microsoft's official yum repo (`packages.microsoft.com/yumrepos/azure-cli`)
- **lazygit** — ships natively in Fedora's own repos (simpler than the Ubuntu script's `go install` build, which is kept only as a fallback if the package isn't found)

---

#### Fedora: Desktop Apps

- **Spotify** — Flathub (`com.spotify.Client`); confirmed no rpm/repo exists from Spotify (their own page lists only Snap + a Debian apt repo, and states Linux isn't actively supported)
- **Slack** — official but **undocumented** vendor repo via `packagecloud.io` (not linked from slack.com's own downloads page, which shows only a standalone rpm + Snap)
- **Remmina** — ships directly in Fedora's own repos at a current version, no PPA equivalent needed the way Ubuntu needs `remmina-ppa-team`
- **Windows App for Linux** — same standalone Flatpak-bundle-from-GitHub-releases mechanism as the Ubuntu script
- **TeamViewer** — official yum repo (`linux.teamviewer.com/yum/stable`), Fedora explicitly listed as supported
- **1Password** — official yum repo (`downloads.1password.com/linux/rpm/stable`); simpler than the Ubuntu apt path since rpm needs no `debsig-verify`-style extra policy step, just the repo + gpgkey

---

#### Fedora: Browsers

Option `26` opens the same All/individual sub-menu shape as the Ubuntu script:

| Browser | Source |
|---------|--------|
| Brave | Official yum repo |
| Vivaldi | Official yum repo |
| Google Chrome | Self-registering official rpm |
| Microsoft Edge | Official yum repo |
| LibreWolf | Official yum repo (supersedes older community COPRs) |
| Zen Browser | Flathub — confirmed no vendor rpm/COPR exists |
| Floorp | Flathub — Ablaze's own docs point to Flathub as the Linux path, no rpm/yum equivalent to `ppa.ablaze.one` |

---

#### Fedora: Communication

Option `27` opens a 5-item sub-menu (**Zoom is not included** — dropped entirely per explicit request during development, unlike the Ubuntu script which doesn't have this category split out this way either):

| App | Source |
|-----|--------|
| Signal | Flathub (`org.signal.Signal`) — confirmed no rpm/yum repo exists anywhere; the commonly-cited `updates.signal.org/desktop/yum/` URL 404s |
| Discord | RPM Fusion nonfree, natively — better than a Flatpak fallback |
| Telegram Desktop | RPM Fusion free, natively — more consistently available than Ubuntu's own `telegram-desktop` apt package |
| Teams (teams-for-linux) | Its own real dnf repo (`repo.teamsforlinux.de/rpm`) |

---

#### Fedora: Drivers & Extra Repos

The Ubuntu script has its own, much smaller Drivers & Extra Repos category (DisplayLink only — no GPU-driver or extra-repo concept beyond that).

| # | Item | What it does |
|---|------|---------------|
| 1 | **NVIDIA Proprietary Driver** | Installs `akmod-nvidia` + `xorg-x11-drv-nvidia-cuda` from RPM Fusion nonfree, then polls `modinfo -F version nvidia` for up to 5 minutes (the kernel module compiles in the background — RPM Fusion's own docs say to expect this). If Secure Boot is detected as enabled, prints the exact `kmodgenca`/`mokutil --import`/reboot-into-MOKManager commands rather than attempting to automate them — enrolling a Secure Boot key is a hardware-firmware-level interactive step no script can complete unattended. |
| 2 | **Terra Repo** | Enables [Terra](https://github.com/terrapkg/packages) (Ultramarine Linux's parent project's general-purpose repo), scoped to the `terra-release-extras` subrepo only — deliberately **not** its alternate Mesa/NVIDIA subrepos, which conflict with RPM Fusion's own and would fight with option 1 above. Prompted opt-in either way. |
| 3 | **DisplayLink Driver** | Fedora carries no DisplayLink RPM in its own repos, so the script downloads the community [displaylink-rpm](https://github.com/displaylink-rpm/displaylink-rpm) project's prebuilt `fedora-<version>-displaylink-*.rpm` GitHub release asset matching the running Fedora version/arch and `dnf install`s it directly — its `%post` handles the DKMS `evdi` build and starts `displaylink-driver.service` itself, nothing left for the script to do afterward. Falls back to a warning pointing at the project's releases page if no matching build exists yet for the running Fedora version. Prompted opt-in, same shape as NVIDIA/Terra — only useful with actual DisplayLink hardware (USB docks/monitors, DL-3xxx–DL-7xxx chipsets). |

---

### 🔀 Fedora Bulk Options (A / B / C)

| Option | Runs | Notes |
| ------ | ---- | ----- |
| **A** | Code Editors, Python, Web Development, Java, C/C++, Go, Rust, Node.js, PHP, Ruby, .NET, General Development Tools, AI Tools | "All Dev Tools" |
| **B** | Creative Suite (Full) | "All Creative" |
| **C** | Everything in A and B, plus Database Tools, Containers & VMs, Gaming, Office & Productivity, System Utilities, GUI Tweaks, Windows Software Support, Android Tools, Security Tools (Full), DevOps & Cloud, Desktop Apps, Browsers, Communication | "EVERYTHING" |

**App folders:** identical behavior to the Ubuntu script — A/B/C **auto-create** a GNOME app folder per category (no prompts); individual numbered categories *ask* first. NVIDIA driver / Terra repo (option `28`) are intentionally **not** part of any bulk option — both are meaningful, semi-interactive opt-ins that shouldn't fire unattended during "EVERYTHING".

---

### 🔧 Fedora Error Handling & Installation Checks

Same three-step check flow as the Ubuntu script (already installed? → exists in repos? → attempt install), just backed by `rpm -q` / `dnf info -q` / `dnf install -y` instead of `dpkg -l` / `apt-cache policy` / `pm_install`. No Nala-style front-end split — `dnf` is `dnf` either way.

| Function | Purpose |
|----------|---------|
| `is_installed(pkg)` | Checks if a package is installed via `rpm -q` |
| `package_exists(pkg)` | Verifies a package exists via `dnf info -q` (checks both installed and available) |
| `bootstrap_repos` | Enables RPM Fusion free+nonfree, AppStream data, and Cisco OpenH264 — runs once, early |
| `add_copr(project, tag)` | Enables a COPR project, degrading gracefully (like `add_ppa`) if it has no build for this release |
| `safe_install(pkgs...)` / `batch_install(category, pkgs...)` | Same shape as the Ubuntu script |
| `create_menu_category(...)` | Same GNOME app-folder feature, `rpm -ql`-based resolution |
| `install_nvidia_driver` | Installs the NVIDIA driver, polls for the akmod build to finish, detects and flags Secure Boot |
| `install_terra_repo` | Opt-in Terra repo setup, scoped to the `extras` subrepo only |

---

### 📊 Fedora Installation Summary & Logging

Identical Catppuccin-themed summary/logging to the Ubuntu script. The only difference is the log path:

```
/var/log/fedora_post_install_TIMESTAMP.log
```

---

### 🔒 Fedora Security Notes

- **Package integrity:** dnf packages are signed by Fedora's own archive keys and RPM Fusion's. Third-party **yum/dnf repos** (VS Code, Brave, Vivaldi, Chrome, Edge, LibreWolf, TeamViewer, 1Password, Cursor, Azure CLI, Slack, Teams) pin their GPG key via `gpgkey=`/`rpm --import`. **COPR** (DBeaver CE) trusts the COPR project owner, whose packages run maintainer scripts as root — same trust model as an Ubuntu PPA.
- **Remote install scripts run as root, trusted over HTTPS only:** Ollama's `install.sh`. Same trust model as the Ubuntu script — TLS + the vendor, no independent checksum.
- **Claude Code, Mistral Vibe CLI, OpenCode, and rustup** are installed **as your user** (via `su - $SUDO_USER`), not root — same reasoning as the Ubuntu script (their installers assume a real `$HOME`).
- **NVIDIA proprietary driver:** a real out-of-tree kernel module (`akmod-nvidia`), signed for Secure Boot only if you complete the MOK enrollment yourself (the script prints the steps but cannot automate the reboot-into-firmware-UI part).
- **Docker/libvirt group = root-equivalent:** installing Docker or libvirt adds your user to the `docker`/`libvirt` group, which grants effective root over that daemon's socket — same caveat as the Ubuntu script.
- **No secrets handled:** the script never asks for or stores passwords/tokens, and menu input (a single character) can't reach a shell.

---

### ⚠️ Fedora Known Limitations

- **Package-name confidence varies by category** — see the note at the top of [Fedora Package Categories](#-fedora-package-categories). The "hard" categories were individually researched and verified; the bulk of ordinary packages weren't re-checked against a live Fedora system (none was available during development), and rely on the `package_exists` safety net instead of a pre-verified list.
- **NVIDIA + Secure Boot needs a manual step**: the script detects Secure Boot and prints the exact commands, but enrolling the MOK key genuinely requires an interactive reboot into a firmware-level UI — no script can complete this unattended.
- **Bulk options don't include Drivers & Extra Repos**: NVIDIA driver, Terra repo, and the DisplayLink driver are deliberately excluded from `A`/`B`/`C` since they're meaningful, semi-interactive opt-ins, not safe to fire unattended.
- **"Ubuntu Studio" categories are consolidated**: the Ubuntu script has separate top-level Graphics/Video/Audio categories *in addition to* its Ubuntu Studio sub-menu (a deliberate overlap there). Fedora has no per-domain metapackage split to mirror that duplication meaningfully, so this port folds all of it into one **Creative Suite** category — a simplification, not an oversight.

---

### ⚙️ Fedora Customization

#### Adding New Packages (Fedora)

```bash
batch_install "Category Name" \
    package1 \
    package2 \
    package3
```

**Important:** verify new packages exist in Fedora's repos (`dnf info -q <pkg>`) before adding them.

#### Creating New Categories (Fedora)

1. Add an install function:
   ```bash
   install_my_category() {
       batch_install "My Category" package1 package2
   }
   ```
2. Add a menu line in `show_main_menu`.
3. Add a case branch in `main()`:
   ```bash
   29) reset_tracking; install_my_category; display_summary; prompt_menu_category "My Category" "icon" "Comment" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
   ```
4. Optionally add the new function to the `A`/`B`/`C` bulk chains in `main()`.

---

### 🐛 Fedora Troubleshooting

| Issue | Solution |
| ----- | -------- |
| **Script exits immediately** | Run with `sudo` |
| **Package not found** | May not be in Fedora's repos yet — check the package name or install manually |
| **Dependency errors** | Run `sudo dnf distro-sync` or `sudo dnf install --allowerasing <pkg>` to resolve conflicts |
| **NVIDIA driver installed but the module won't load** | Check Secure Boot status: `mokutil --sb-state`. If enabled, the MOK key must be enrolled manually — see the exact commands the script prints, or [Fedora: Drivers & Extra Repos](#fedora-drivers--extra-repos) above |
| **`akmods --status` shows a failed build** | Usually means kernel headers are missing or out of sync after a kernel update — `sudo akmods --force` after a reboot into the new kernel often fixes it |
| **App folder not created** | Same requirement as the Ubuntu script — needs an active GNOME desktop session as the target user |
| **"Designed for Fedora NN/NN, detected: …"** | You're on a release the script isn't validated against — answer `y` to continue anyway, or add your version to `SUPPORTED_VERSIONS` at the top of the script |

#### Checking Fedora Logs

```bash
# View a specific log
cat /var/log/fedora_post_install_*.log

# Tail the most recent
ls -lt /var/log/fedora_post_install_*.log | head -1 | awk '{print $NF}' | xargs cat
```

---

# 🏹 Arch Linux / Omarchy Post-Install Script

### 🚀 Arch Overview

[`post-install-arch.sh`](post-install-arch.sh) is the Arch/Omarchy port of `post-install-fedora.sh` — same category taxonomy, same Catppuccin-themed menu UX, same installed/skipped/failed tracking — rebuilt on **`pacman`** with a **`yay`** AUR fallback instead of `dnf`. It explicitly targets two things:

- **Plain Arch Linux.**
- **[Omarchy](https://omarchy.org)** — an opinionated Arch distro built on Hyprland + a custom Quickshell desktop shell, shipped as an ISO and updated via real pacman packages rather than a curl\|bash overlay. Reviewed against Omarchy v4.0.0 ("Quattro") during development.

Two things follow directly from also targeting Omarchy:

1. **Omarchy already owns the whole desktop layer** — Hyprland, its own Quickshell bar/launcher/notifications/lock-screen/theme system, terminal (Foot), editor (Neovim), browser (Chromium), file manager (Nautilus), screenshot tool, and even nine pre-wired AI coding-agent CLIs via mise stubs. This script never tries to install or theme a desktop environment on top of that — the GNOME-specific helpers (app-folders, terminal-font, Shell extensions) only do anything if a GNOME session is genuinely running, which is never true on Omarchy and only true on a plain-Arch-plus-GNOME box.
2. **Omarchy guards raw pacman syncs.** Since v4.0.0 it ships a pacman pre-transaction hook that aborts any direct full-sync (`pacman -Sy`/`-Syu`) not launched through `omarchy update`. The script never runs a raw `-Syu` when Omarchy is detected — only targeted `pacman -S <pkg>` installs, which the guard doesn't touch.

Everywhere Omarchy already provides a first-party wrapper for something this script would otherwise hand-roll (theme switching, NVIDIA driver selection, Btrfs snapshots, web-app `.desktop` files), the script **detects and defers to that wrapper** instead of duplicating its logic — see [Omarchy-Specific Behavior](#-omarchy-specific-behavior) below for the full list.

**Package-name confidence note:** Arch has no RPM-Fusion/COPR-style curated third-party layer — "not in the official repos" here almost always means "check the AUR," not "unavailable." `safe_install` therefore tries the official repos first and transparently falls back to the AUR (via `yay`) per package, following the same verification spirit as the Fedora script's own confidence notes. `is_installed`/`package_exists` still gate every install, so a wrong guess is logged "Not in repos or AUR" and skipped rather than failing the whole run.

---

### ✨ Arch Features

#### Arch Core Features

| Feature | Description |
| --- | --- |
| **Omarchy Detection** | Detects Omarchy vs. plain Arch at startup and adapts menus, driver installs, theming, and update behavior accordingly |
| **pacman + AUR (yay) Front-End** | `safe_install` checks official repos first, falls back to AUR via `yay` per package — no single-source assumption |
| **AUR Bootstrap** | Installs `yay` from **yay-bin** (prebuilt, no Go toolchain needed) if missing; no-op on Omarchy, which ships it by default |
| **Temporary Passwordless-Sudo Workaround** | Grants (and always revokes via `trap`) a narrowly-scoped `NOPASSWD: /usr/bin/pacman` rule so `yay` can call `sudo pacman` mid-build without a broken TTY chain |
| **Catppuccin-Themed Output** | Same palette/menus/logging as the Ubuntu/Fedora scripts, auto-disabled for non-TTY / `NO_COLOR` |
| **Interactive Menu** | Text-based menu with 30 categories, plus Creative Suite, Security, Browsers, Communication, GUI Tweaks, GTK Themes, Drivers, Snapshots, and Peripherals sub-menus |
| **GNOME App-Folder Creation** | Same feature as Ubuntu/Fedora, `pacman -Qlq`-based resolution — explicitly a no-op under Hyprland/Omarchy (no GNOME session to target) |
| **Snapshots & Backup Category** | New category with no Fedora/Ubuntu equivalent — Btrfs + Snapper + grub-btrfs, or Timeshift on non-Btrfs roots; Omarchy-aware (won't fight Omarchy's own Snapper/Limine setup) |
| **BlackArch & Chaotic-AUR Repo Bootstraps** | Opt-in third-party repo setups under Drivers & Extra Repos — BlackArch's official `strap.sh` with a manual checksum cross-check, Chaotic-AUR's signed keyring/mirrorlist |
| **NVIDIA Driver Support** | Defers to Omarchy's own `omarchy-apply-hardware` hardware detector when present; otherwise a manual DKMS-based install with dynamic kernel-headers detection and Secure Boot guidance |
| **Manjaro / Garuda Awareness** | Manjaro gets a hard confirmation gate warning that this script's AUR-heavy flow risks breaking Manjaro's intentionally-delayed package branch; Garuda gets an informational note that Chaotic-AUR/Snapper are typically already enabled there |
| **Error Handling** | Skips unavailable packages, continues installation |
| **Installation Tracking** | Tracks installed, skipped, and failed packages per run — AUR-sourced installs are tagged `(AUR)` in the summary |
| **Summary Reporting** | Shows detailed installation summary with the "S" command |
| **Log Saving** | Saves complete logs to `/var/log/arch_post_install_TIMESTAMP.log`, recording "Omarchy `<version>`" or "Arch Linux" as the detected system type |

#### Arch Statistics

- **Main Menu Categories:** 30 (Snapshots & Backup is hidden from the on-screen list on Omarchy but still reachable if typed directly), plus Creative Suite, Security, Browsers, Communication, GUI Tweaks, GTK Themes, Drivers, Snapshots, and Peripherals sub-menus
- **Package Front-End:** `pacman`, with `yay` bootstrapped automatically for AUR fallback
- **AUR-Sourced Tools (no official-repo package exists):** VS Code, Sublime Text, Cursor, most browsers (Brave, Edge, Chrome, Zen, Floorp), Spotify, Slack, TeamViewer, 1Password, teams-for-linux, virtio-win, DisplayLink driver, and several security tools (`whatweb`, `wfuzz`, `sleuthkit-git`, `steghide`, `chkrootkit`, `aide`, `suricata`)
- **Official-Repo Wins Over Fedora/Ubuntu:** Vivaldi, LibreWolf, Signal, Discord, Telegram, DBeaver, Azure CLI, lazygit, scrcpy, and most of the Security Tools "Firewall & Privacy" batch all land directly in Arch's `[extra]` repo — no vendor repo, COPR, or RPM Fusion dance needed
- **Flatpak-Only (last resort, no reliable repo/AUR alternative):** Alpaca, Bruno, IntelliJ IDEA Community, Windows App for Linux
- **Estimated Install Time:** 15 minutes – several hours (AUR builds compile from source, so individual packages can be noticeably slower than Fedora/Ubuntu's prebuilt binaries, especially without Chaotic-AUR enabled)
- **Estimated Disk Space:** 5–30GB+ (depending on selections)

---

### 📥 Arch Installation

#### Prerequisites

- **Arch Linux or Omarchy** — no formal version gate (rolling release); the script detects Omarchy vs. plain Arch and adapts automatically
- **Root access** (script must be run with `sudo`)
- **A real non-root user session** (`$SUDO_USER`) for anything that touches the AUR — `yay`/`makepkg` refuse to run as root
- **Internet connection**
- **An active GNOME desktop session** if you want app folders created on a plain-Arch+GNOME box — meaningless (and skipped) on Omarchy/Hyprland

#### Quick Start

```bash
chmod +x post-install-arch.sh
sudo ./post-install-arch.sh
```

---

### 🎯 Arch Usage

#### Running the Script

```bash
chmod +x post-install-arch.sh
sudo ./post-install-arch.sh
```

At startup the script runs `bootstrap_arch` (installs `yay` if missing, enables `[multilib]`) and `update_packages` — a full `pacman -Syu` on plain Arch (deliberate: the Arch Wiki warns a bare `-Sy` without an immediate `-u` risks a partial-upgrade break), but this step is **entirely skipped on Omarchy** because of its update-guard hook — you'd run `omarchy update` for that instead.

#### Menu Navigation

1. **Main Menu**: numbered categories `0`–`30`, grouped on screen into Creative & Drivers, Development, Data/System/Desktop, Compatibility & Devices, and Internet & Communication
2. **Sub-Menus**: Creative Suite (`1`), Security Tools (`22`), Browsers (`26`), Communication (`27`), GUI Tweaks/Theming (`19`, itself branching into a GTK Themes sub-menu), Drivers & Extra Repos (`28`), Snapshots & Backup (`29`), Peripherals (`30`) each open their own sub-menu
3. **Bulk Options**: `A` (All Dev Tools), `B` (All Creative), `C` (EVERYTHING) — see [Bulk Options](#-arch-bulk-options-a--b--c) below
4. **`S`** — Show Installation Summary
5. **`0`** — Exit

The menu subtitle line reads differently depending on what's detected: `pacman · AUR (yay) · GNOME app folders (if present)` on plain Arch, or `pacman · AUR (yay) · Omarchy <version>` on Omarchy.

#### Example Workflows

##### Install a Development Environment

```bash
sudo ./post-install-arch.sh
# Select: 2 (Code Editors)
# Select: 4 (Web Development)
# Select: 18 (AI Tools)
# Press 0 to exit
```

##### Install Creative/Media Tools

```bash
sudo ./post-install-arch.sh
# Select: 1 (Creative Suite) -> 1 (Full)
# -> installs Graphics & Design, Video Editing, Audio Production, Photography, Publishing
```

##### Set Up Containers & VMs

```bash
sudo ./post-install-arch.sh
# Select: 13 (Containers & VMs)
# -> installs Docker/Podman, KVM/QEMU + virt-manager/GNOME Boxes, Cockpit, and the docker/libvirt bridge-forwarding fix
```

##### Full System Setup

```bash
sudo ./post-install-arch.sh
# Select: C (EVERYTHING)
# Wait for completion (AUR builds make this the slowest of the three scripts' full runs)
```

---

### 🗂️ Arch GNOME App Folders (Super Key Groups)

Same feature and same `org.gnome.desktop.app-folders` gsettings mechanism as the Ubuntu/Fedora scripts, with an Arch-specific resolution order: a package's own file list (`pacman -Qlq`) first, then a dependency walk for meta-packages with no launcher of their own, then a reverse-DNS prefix guess, then a Flatpak-exports match for Flatpak-only tools (Alpaca, Bruno, IntelliJ, Windows App).

**On Omarchy this feature is a deliberate, explicit no-op.** `prompt_menu_category` detects Omarchy and, instead of prompting, logs: *"Omarchy's app launcher (Super+Space) already fuzzy-searches every installed app — no GNOME-style menu folder needed"* — then does a bare pause so the category's install summary doesn't flash by and vanish (the confirmation prompt that normally provides that pause is what's being skipped). Bulk-run categories (`A`/`B`/`C`) call `create_menu_category` directly and unprompted either way — still a no-op if no GNOME `app-folders` schema is present.

---

### 📦 Arch Package Categories

Below is a breakdown of what each category installs. Packages are tagged **(AUR)** where Arch has no official-repo equivalent; everything else is `[extra]`/`[core]`/`[multilib]`.

---

#### Arch: AI Tools

| Tool | Installation Method |
| --- | --- |
| **Ollama** | Official install script |
| **Alpaca** | Flathub (`com.jeffser.Alpaca`) — no reliable AUR package |
| **Claude Code** | Official native installer, npm fallback |
| **Claude Desktop** | AppImage downloaded directly from [aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian)'s GitHub Releases — its own AUR package (`claude-desktop-appimage`) was deleted 2026-08-01 in an AUR duplicate-package cleanup and is pending reinstatement, so the script hand-writes a `.desktop` launcher instead of waiting on it |
| **Gemini CLI** | `npm install -g @google/gemini-cli` |
| **Mistral Vibe CLI** | Official installer script (needs Python 3.12+) |
| **OpenCode** | Official native installer, npm fallback |
| **Cursor** | **(AUR)** `cursor-bin` — simpler than Fedora's yum-repo bootstrap, no repo registration needed |

**Omarchy note:** it pre-wires nine coding-agent CLIs (`claude`, `codex`, `opencode`, `gemini`, `copilot`, `crush`, `grok`, `pi`, `omp`) as lazy-loading mise stubs already on `$PATH` — no special-casing needed, every function here already gates on `command -v` first and just reports "already installed." Ollama, Alpaca, Claude Desktop, and Cursor aren't among those nine stubs, so they still install fresh even on Omarchy.

---

#### Arch: Code Editors

**Official repo:** `vim`, `neovim`, `emacs`, `nano`, `geany`, `gnome-text-editor`, `gedit`, `kate`

**AUR:** `visual-studio-code-bin` (VS Code has **no** official-repo package on Arch at all — even the community OSS build is AUR-only), `sublime-text-4`

**Bruno** — Flathub (`com.usebruno.Bruno`); AUR entries have historically been flaky/unmaintained

**LazyVim + Nordic (optional prompt):** same opt-in as Ubuntu/Fedora — backs up any existing `~/.config/nvim` first (this correctly catches and backs up Omarchy's own `omarchy-nvim` config too, with no special-casing needed).

---

#### Arch: Python

`python`, `python-pip`, `python-virtualenv`, `ipython`, `python-pipx`

---

#### Arch: Web Development

`nginx`; `apache`, `php-fpm`, `php`, `composer` (not started, mirroring the Ubuntu/Fedora port-80 avoidance); Node.js + the same global npm package set as [Node.js Development](#arch-nodejs).

---

#### Arch: Java

`jdk-openjdk`, `gradle`, `maven`, `ant`, `junit` — Arch has no separate javadoc split package (bundled into `jdk-openjdk`). Plus IntelliJ IDEA Community via Flathub (`com.jetbrains.IntelliJ-IDEA-Community`).

---

#### Arch: C/C++

`gcc`, `gcc-fortran`, `clang`, `cmake`, `make`, `ninja`, `ccache`, `autoconf`, `automake`, `libtool`, `m4`, `bison`, `flex`, `gettext`, `pkgconf`, `cppcheck`, `valgrind`, `gdb`, `ltrace`, `strace`

---

#### Arch: Go

The official package is simply `go` (not `golang`) — installed directly if `go` isn't already on `PATH`.

---

#### Arch: Rust

Prefers `rustup` (installed as your user into `~/.cargo/bin`, matching Ubuntu/Fedora's approach); falls back to the official `rust` package, which bundles `rustc`+`cargo`+stdlib as one package with no split.

---

#### Arch: PHP

`php`, `php-fpm`, `php-gd`, `php-curl`, `php-pgsql`, `php-sqlite`, `composer` — unlike Fedora, Arch doesn't split out `php-xml`/`php-mbstring`/`php-json`; they're compiled into the base `php` package.

---

#### Arch: Ruby

`ruby`, `ruby-bundler` — rubygems ships bundled inside `ruby`, not as a separate package.

---

#### Arch: Node.js

Same installer as [Web Development](#arch-web-development): `nodejs`, `npm`, plus global packages `npm-check-updates`, `nodemon`, `pm2`, `webpack`, `webpack-cli`, `eslint`, `prettier`.

---

#### Arch: .NET

`dotnet-sdk`, `aspnet-runtime` — both landed in the official `[extra]` repo; no longer requires a Microsoft-maintained AUR package.

---

#### Arch: General Dev Tools

`jq`, `tig`, `subversion`, `make`, `cmake`, `autoconf`, `automake`, `bison`, `flex`, `gettext`, `pkgconf`, `man-db`, `man-pages`, `less`, plus Bruno (see [Code Editors](#arch-code-editors)).

---

#### Arch: DevOps & Cloud

- **Docker + docker-compose** — dedicated standalone install, enables the service, adds the invoking user to the `docker` group
- **Azure CLI** — official `[extra]` package `azure-cli` (no longer AUR-only)
- **lazygit** — official `[extra]` package (unlike Fedora's historical `go install`/COPR fallback)

---

#### Arch: Database Tools

`mariadb`, `sqlite`, `sqlitebrowser`, `memcached`, and **`valkey`** (Redis-compatible) — Arch moved `redis` to AUR/deprecated status and replaced it in `[extra]` with `valkey` in 2024 over Redis's license change (the same dispute driving Fedora's own valkey default), so unlike Fedora there's no "offer both" choice here.

`postgresql` is initialized via `sudo -u postgres bash -c "initdb ..."` — deliberately **not** `su - postgres -c`, since Arch's `postgres` system user has shell `/usr/bin/nologin`, which would silently no-op under `su -`. MariaDB gets an explicit first-run `mariadb-install-db` (Arch's package, unlike Debian/Fedora's, doesn't do this in a post-install scriptlet).

**DBeaver** — official `[extra]` package `dbeaver` directly, no COPR/third-party repo needed.

---

#### Arch: Containers & VMs

**Containers:** `docker`, `docker-compose`, `podman`, `iptables` (explicit — Arch's docker package depends on nftables, and libvirt only optionally suggests `iptables-nft`, needed for the bridge-forward fix below). Docker enabled, user added to the `docker` group.

**Virtualization:** `qemu-full`, `libvirt`, `virt-install`, `virt-manager`, `virt-viewer`, `gnome-boxes`, `cockpit`, `cockpit-machines`, `cockpit-podman`. `libvirtd` enabled, user added to the `libvirt` group.

**Virtio-Win drivers:** tries the **(AUR)** `virtio-win` package first (its own PKGBUILD drops the ISO straight into `/var/lib/libvirt/images/virtio-win.iso`, no symlink detour needed like Fedora's RPM); falls back to a direct download of upstream's "stable" ISO if the AUR build is unavailable.

**Docker/libvirt bridge-forward fix:** the same Docker-sets-FORWARD-to-DROP-without-scoping issue documented in the Ubuntu/Fedora sections — a systemd oneshot service inserts `DOCKER-USER` ACCEPT rules for libvirt's `virbr+` bridges idempotently, `After=`/`Wants=` both `docker.service` and `libvirtd.service`.

---

#### Arch: Gaming

`steam`, `lutris`, `gamemode`, `mangohud`, `lib32-gamemode`, `lib32-mangohud` (multilib enabled first). The user is explicitly added to the **`gamemode`** group — unlike Fedora, Arch's `gamemode` package does **not** auto-enroll the user, so without this `gamemoded` is denied permission to change the CPU governor/niceness.

**Omarchy note:** Omarchy ships its own on-demand installers (`omarchy-install-gaming-steam`, `-lutris`, `-gpu-lib32`), but running this category doesn't conflict — `safe_install` just no-ops on anything already installed.

---

#### Arch: Windows Software Support

`wine`, `wine-mono`, `wine-gecko`, `winetricks`, `zenity` (multilib enabled first); a `winetricks.desktop` GUI launcher is written since the package ships none.

---

#### Arch: Browsers

Nearly every browser here needed a hand-rolled vendor-repo dance on Fedora; on Arch almost all have a well-established AUR `-bin` package or land directly in `[extra]`.

| Browser | Source |
| --- | --- |
| Brave | **(AUR)** `brave-bin` |
| Vivaldi | Official `[extra]` |
| Microsoft Edge | **(AUR)** `microsoft-edge-stable-bin` |
| Google Chrome | **(AUR)** `google-chrome` (repackages Google's official `.deb`; occasionally breaks briefly if Google changes URLs, fixed fast given 2000+ AUR votes) |
| LibreWolf | Official `[extra]` |
| Zen Browser | **(AUR)** `zen-browser-bin` (avoids the from-source `zen-browser` package's heavy rust/llvm/wasi toolchain) |
| Floorp | **(AUR)** `floorp-bin` — no Flathub fallback needed here, unlike Fedora |

---

#### Arch: Communication

| App | Source |
| --- | --- |
| Signal | Official `[extra]` (`signal-desktop`) — vs. Fedora's dedicated vendor repo |
| Discord | Official `[extra]` — vs. Fedora's RPM Fusion nonfree requirement |
| Telegram | Official `[extra]` (`telegram-desktop`) — vs. Fedora's RPM Fusion requirement |
| Microsoft Teams | **(AUR)** `teams-for-linux` — same community project Ubuntu/Fedora consume via their own repos |

---

#### Arch: Desktop Apps

| App | Source |
| --- | --- |
| Spotify | **(AUR)** `spotify` |
| Slack | **(AUR)** `slack-desktop` — no manual release-note version-scraping needed, unlike Fedora |
| Remmina | Official `[extra]` `remmina` + `freerdp` (explicit — freerdp is only an optional dep) |
| TeamViewer | **(AUR)** `teamviewer` — community-maintained, no official vendor support; the AUR package has carried an out-of-date flag before |
| 1Password | **(AUR)** `1password` — not on Arch/AUR's officially-supported platform list, unlike Fedora's rpm/Ubuntu's deb |
| Windows App for Linux | No AUR package exists — the script queries GitHub's API for the latest [mariuszkopowski/windows-app-for-linux](https://github.com/mariuszkopowski/windows-app-for-linux) release, downloads the `.flatpak` asset, and installs it into the desktop user's per-user Flatpak scope |

---

#### Arch: Creative Suite

Fedora uses `dnf` comps groups ("Fedora Jam", "Design Suite") for this; Arch has **no equivalent metapackage/group at all**, so every sub-category here is hand-curated.

- **Graphics & Design:** `gimp`, `inkscape`, `krita`, `blender`, `darktable`, `pitivi`, `qimgv` (swapped in for `nomacs` — its AUR package depends on a nonexistent `quazip-qt6`, confirmed via a live AUR query; `qimgv` fills the same role from the same maintainer), `flameshot`, `imagemagick`, `graphicsmagick`, `optipng`, `jpegoptim`, `pngquant`, `libwebp`. Also binds Print Screen to `flameshot gui` via gsettings on GNOME (explicit no-op on Omarchy, which has its own `omarchy-capture-*` screenshot tooling).
- **Video Editing:** `kdenlive`, `shotcut`, `obs-studio`, `mkvtoolnix-cli`, `mkvtoolnix-gui`, `mpv`, `vlc`, `yt-dlp`, plus multimedia codecs (`ffmpeg` — already the full/unencumbered build on Arch, no swap needed like Fedora's `ffmpeg-free`→`ffmpeg`; `gst-plugins-good/bad/ugly`, `gst-libav`).
- **Audio Production:** `ardour`, `audacity`, `carla`, `hydrogen`, `guitarix`, `qjackctl`, `lsp-plugins-lv2`, `calf`, `libpulse`, `soundconverter`, `easytag`, `pavucontrol`.
- **Photography:** `darktable`, `rawtherapee`, `digikam`, `hugin`, `gthumb`.
- **Publishing:** `scribus`, `fontforge`, `calibre`.
- **Full** — runs Graphics, Video, Audio, Photography, and Publishing in sequence.

---

#### Arch: Office & Productivity

`libreoffice-fresh`, `okular`, `evince`, `zathura`, `pandoc-cli` (bare `pandoc` doesn't exist as a package name on Arch — that's the Haskell library, `haskell-pandoc`).

---

#### Arch: System Utilities

`htop`, `iotop`, `sysstat`, `glances`, `nethogs`, `iftop`, `nload`, `vnstat`, `tcpdump`, `wireshark-cli`, `wireshark-qt` (Arch splits Wireshark into a core/tshark package and a separate Qt GUI, unlike Fedora's single package), `lsof`, `strace`, `ltrace`, `valgrind`, `gdb`, `tmux`, `screen`, `zsh`, `fish`, `fzf`, `ripgrep`, `tree`, `ncdu`, `rsync`, `unzip`, `bat`.

---

#### Arch: Android Tools

`android-tools`, `android-udev`, `scrcpy` — `scrcpy` lands directly in `[extra]` (depends on `android-tools`), no COPR needed like Fedora.

---

#### Arch: Security Tools

Same Full/Defensive-only sub-menu split as Ubuntu/Fedora, installed in themed batches — notably, Arch's **Firewall & Privacy** batch (`firewalld`, `firewall-config`, `openvpn`, `wireguard-tools`, `proxychains-ng`, `torsocks`, `keepassxc`, `ettercap`) is **entirely official-repo**, needing no AUR or BlackArch fallback at all, unlike Fedora.

- **Network:** `nmap` (bundles `ncat` itself, unlike Fedora's separate package), `masscan`, `hping`, `bind` (provides `dig`/`nslookup`; Fedora calls this package `bind-utils`)
- **Web app testing:** `nikto`, `sqlmap`, `gobuster` (all landed in `[extra]`, previously AUR/BlackArch-only), **(AUR)** `whatweb`, `wfuzz` (both carry real maintenance risk — `whatweb` flagged by its own maintainer for possible removal, `wfuzz` has open Python 3.13 build issues)
- **Cracking & wireless:** `john`, `hashcat`, `hydra`, `aircrack-ng`, `macchanger` — all official, including macchanger (Fedora needs a third-party repo for it)
- **Forensics & RE:** `radare2`, `binwalk`, **(AUR)** `sleuthkit-git` (no plain `sleuthkit` package exists anywhere), **(AUR)** `steghide` (open unresolved libjpeg-turbo build issue), `yara`, `perl-image-exiftool`
- **Hardening:** `lynis`, **(AUR)** `chkrootkit`, `rkhunter`, `clamav` (bundles freshclam directly), `fail2ban`, **(AUR)** `aide`
- **Firewall & Privacy:** `firewalld`, `firewall-config`, `openvpn`, `wireguard-tools`, `proxychains-ng`, `torsocks`, `keepassxc`, `ettercap` — if firewalld installs, the script notes Arch's more idiomatic minimal alternative is `ufw`, and never installs both (they conflict)

**Defensive only:** `lynis`, `chkrootkit`, `rkhunter`, `aide`, `audit` (in Arch's `[core]`, often already present), `clamav`, `fail2ban`, **(AUR)** `suricata`, `firewalld`, `firewall-config`, `openvpn`, `wireguard-tools`, `keepassxc`.

**BlackArch repo (opt-in):** downloads BlackArch's official `strap.sh`, computes its SHA1, and asks you to manually cross-check it against blackarch.org's published value before running it (a hardcoded checksum would go stale — see [BlackArch/blackarch#1249](https://github.com/BlackArch/blackarch/issues/1249)). Carries an extra Omarchy-specific warning about layering an uncurated repo on top of Omarchy's curated package set.

**Chaotic-AUR repo (opt-in):** same risk profile/warning shape as BlackArch — imports Chaotic-AUR's signing key, installs its keyring/mirrorlist packages via direct `pacman -U`, and appends a `[chaotic-aur]` section to `/etc/pacman.conf` (Chaotic-AUR's own docs recommend it precede other third-party repos there). Also enables multilib first, since Chaotic-AUR's docs list it as a flat prerequisite.

---

#### Arch: Peripherals (Logitech)

`solaar` (udev rules bundled in the main package, no separate `-udev` split). A dedicated fix — `solaar config "MX Anywhere 3S" hires-smooth-resolution 1` — addresses a real hardware issue: the MX Anywhere 3S over Bluetooth ships with its "Scroll Wheel Resolution" HID++ feature disabled by default, causing slow-but-smooth scrolling that no OS-level setting can fix.

---

#### Arch: Drivers & Extra Repos

| # | Item | Notes |
| --- | --- | --- |
| 1 | **NVIDIA Driver** | **Omarchy:** re-invokes `omarchy-apply-hardware --install-user <user>` (its documented idempotent hardware-redetection entry point) rather than re-deriving GPU classification logic — Omarchy's own tooling picks `nvidia-open-dkms` (GSP-capable: Turing/Ampere/Ada/Blackwell) vs. `nvidia-580xx-dkms` (pre-GSP: Maxwell/Pascal) via sysfs detection. **Plain Arch:** installs `nvidia-open-dkms`, `nvidia-utils`, `lib32-nvidia-utils`, `libva-nvidia-driver` plus dynamically-detected kernel `-headers` packages (matches `linux`/`linux-zen`/`linux-lts`/`linux-hardened`) — DKMS is chosen deliberately over the plain `nvidia` package so it survives kernel updates on non-stock kernels. Writes `modeset=1` and an mkinitcpio hook; prints MOK-enrollment instructions if Secure Boot is enabled |
| 2 | **BlackArch Repo** | Opt-in — see [Security Tools](#arch-security-tools) above |
| 3 | **Chaotic-AUR Repo** | Opt-in — see [Security Tools](#arch-security-tools) above |
| 4 | **DisplayLink Driver** | **(AUR)** `displaylink` (pulls in `evdi-dkms` automatically); installs matching kernel headers first; explicitly enables `displaylink.service` (Arch packaging convention discourages auto-enabling services, unlike Fedora's RPM `%post`) |

---

#### Arch: Snapshots & Backup

**New category with no Fedora/Ubuntu equivalent.** Detects the root filesystem type and routes accordingly:

- **Btrfs root:** installs `snapper`, `grub-btrfs`, `btrfs-assistant`; creates a Snapper `root` config; enables `snapper-timeline.timer`/`snapper-cleanup.timer`; conditionally enables `grub-btrfsd.service` only if GRUB is the actually-detected bootloader (useless — and left disabled — under Limine or systemd-boot). **On Omarchy**, if its own Snapper `root` config already exists, the script deliberately does **not** re-create it or re-enable the timeline timer — Omarchy intentionally disables that timer in favor of update-triggered + manual snapshots via `limine-snapper-sync`, and re-enabling it would fight that choice. `btrfs-assistant` is still installed either way as a standalone GUI.
- **Non-Btrfs root:** falls back to `timeshift`.
- **Create a snapshot now:** prefers `omarchy-snapshot create` on Omarchy (wraps Snapper across every configured config, cleans up by count); else Snapper directly on a Btrfs root; else Timeshift.
- **List snapshots / Open GUI:** Snapper list or `timeshift --list`; `btrfs-assistant` GUI if installed, else Omarchy's own `omarchy-snapshot restore` (interactive `limine-snapper-restore`) with a confirmation prompt, else `timeshift-gtk`.

---

#### Arch: GUI Tweaks / Theming

This menu **branches entirely on Omarchy vs. plain Arch**, since Omarchy already owns theming/terminal/Shell:

- **On Omarchy:** the sub-menu only offers Nerd Fonts, Chris Titus mybash, and an **Omarchy theme picker** (wraps `omarchy-theme-switcher`, or lists themes via `omarchy-theme-list` with manual `omarchy-theme-set` instructions if the switcher isn't available).
- **On plain Arch:** the full set below is offered.

**Icon Sets:** `papirus-icon-theme`, `numix-icon-theme-git` (the original `numix-icon-theme` name is no longer packaged, only this community rebuild), `breeze-icons`, `adwaita-icon-theme`, plus [Qogir](https://github.com/vinceliuice/Qogir-icon-theme), [WhiteSur](https://github.com/vinceliuice/WhiteSur-icon-theme), [Vimix](https://github.com/vinceliuice/Vimix-icon-theme), and [Newaita](https://github.com/cbrnix/Newaita) built/copied from source, same as the Ubuntu script's approach.

**GTK Themes:** [Nordic](https://github.com/EliverLara/Nordic), [Colloid](https://github.com/vinceliuice/Colloid-gtk-theme), [Material GNOME](https://github.com/SakibShahariar/material-gnome-theme), and [Lycia](https://github.com/Aevstiel/Lycia-Theme) — the last piped `Y`/`N` answers (yes to GTK4/libadwaita files, no to the GDM login-screen theme, same unattended-safety reasoning as the Ubuntu script).

**Cursor Themes:** `capitaine-cursors`, `xcursor-breeze5` (breeze-icons ships no XCursor files of its own).

**Nerd Fonts:** prefers official `ttf-*-nerd` pacman packages (FiraCode, JetBrainsMono, Hack, SourceCodePro, CascadiaCode, UbuntuMono, DejaVu) over GitHub-release downloads, only falling back to a direct download for whatever pacman doesn't cover.

**GUI Tools:** `gnome-tweaks`, `nautilus`, `loupe` (swapped in for `eog`, which is being phased out upstream — the script checks and adapts automatically), `file-roller`, `simple-scan`, `gnome-screenshot`, `gnome-system-monitor`, `dconf-editor`. **Explicit no-op on Omarchy** (no GNOME session).

**GNOME Shell Extensions:** same curated set and `gext`/pipx install method as Ubuntu/Fedora. **Explicit no-op on Omarchy**, which replaces GNOME Shell entirely with its own Quickshell desktop.

**Chris Titus mybash:** same clone-and-run pattern as Ubuntu/Fedora, root-run `setup.sh` for the nested-sudo-needs-a-real-terminal reason, falling back to a plain config copy.

**Logiops (optional prompt):** builds [PixlOne/logiops](https://github.com/PixlOne/logiops) from source, writes a default `/etc/logid.cfg` (smartshift + hi-res scroll), enables the `logid` service.

---

### 🔀 Arch Bulk Options (A / B / C)

| Option | Runs | Notes |
| --- | --- | --- |
| **A** | Code Editors, Python, Web Development, Java, C/C++, Go, Rust, Node.js, PHP, Ruby, .NET, General Dev Tools, AI Tools | "All Dev Tools" — 13 categories |
| **B** | Creative Suite (Full) | "All Creative" — a single call |
| **C** | Everything in A and B, plus Database Tools, Containers & VMs, Gaming, Office & Productivity, System Utilities, GUI Tweaks, Windows Software Support, Android Tools, Security Tools, Browsers, Communication, Desktop Apps | "EVERYTHING" — 27 categories total |

**Deliberately excluded from all bulk options:** Peripherals, Drivers & Extra Repos (NVIDIA/BlackArch/Chaotic-AUR/DisplayLink), and Snapshots & Backup — same reasoning as Fedora's exclusion of its Drivers category: these are meaningful, semi-interactive opt-ins, not safe to fire unattended. Every bulk-run category attempts `create_menu_category` unprompted (no-op on Omarchy).

---

### 🔧 Arch Error Handling & Installation Checks

Same three-step check flow as Ubuntu/Fedora (already installed? → exists somewhere? → attempt install), extended with an AUR fallback tier:

```
1. Check if package is ALREADY INSTALLED (pacman -Qq)
   ↓ Yes → Skip (SKIPPED_PACKAGES)
   ↓ No
2. Check if package EXISTS in an official repo (pacman -Si)
   ↓ Yes → Install via pacman -S --needed --noconfirm
   ↓ No
3. Check if package EXISTS in the AUR (yay -Si, only if yay is available)
   ↓ Yes → Install via yay (tagged "(AUR)" in tracking)
   ↓ No → Fail ("Not in repos or AUR")
```

| Function | Purpose |
| --- | --- |
| `is_installed(pkg)` | `pacman -Qq` |
| `repo_package_exists(pkg)` | `pacman -Si` |
| `aur_package_exists(pkg)` | `yay -Si`, only if `yay` is present |
| `package_exists(pkg)` | `repo_package_exists \|\| aur_package_exists` |
| `ensure_yay()` | Bootstraps `yay` from **yay-bin** (no Go toolchain needed); runs the clone/build as `$SUDO_USER` since `makepkg` refuses to run as root, and only the final `pacman -U` runs as root; no-op on Omarchy |
| `enable_temp_passwordless_sudo()` / `disable_temp_passwordless_sudo()` | Grants a narrowly-scoped, temporary `NOPASSWD: /usr/bin/pacman` rule via a `visudo -c`-validated `/etc/sudoers.d/` drop-in so `yay` can call `sudo pacman` from inside the `su`-as-user context without hitting "sudo: a terminal is needed to read the password" — removed via `trap` on exit no matter how the script terminates |
| `aur_install(pkg)` | `su - $SUDO_USER -c "yay -S --needed --noconfirm --removemake '$pkg'"` — deliberately not silenced, so real build failures stay visible |
| `safe_install(pkgs...)` / `batch_install(category, pkgs...)` | Same shape as Ubuntu/Fedora, extended with the AUR tier above |
| `bootstrap_multilib()` | Enables `[multilib]` by uncommenting Arch's existing commented-out block in `/etc/pacman.conf`, rather than appending a duplicate section (a documented real footgun) |
| `update_packages()` | Full `pacman -Syu` on plain Arch (the Arch Wiki warns against a bare `-Sy`); entirely skipped on Omarchy due to its update-guard hook |
| `create_menu_category(...)` | Same GNOME app-folder feature; explicit no-op path on Omarchy |

---

### 📊 Arch Installation Summary & Logging

Same Catppuccin-themed summary as Ubuntu/Fedora. AUR-sourced packages appear in the summary with a trailing `(AUR)` so you can see repo vs. AUR provenance at a glance. Logs save to:

```
/var/log/arch_post_install_TIMESTAMP.log
```

recording the detected system type as either `Omarchy <version>` or `Arch Linux`.

---

### 🐉 Omarchy-Specific Behavior

Because Omarchy already owns so much of the desktop/system layer, this script defers to Omarchy's own tooling in more places than any other category in this repo. Full list:

- **AI Tools** — Omarchy's nine pre-wired mise-stub CLIs mean most AI tool installs just report "already installed" and move on.
- **NVIDIA Driver** — re-invokes `omarchy-apply-hardware --install-user <user>` instead of re-deriving GPU-generation classification logic.
- **Snapshots & Backup** — detects and preserves Omarchy's own Snapper `root` config and its deliberately-disabled timeline timer (in favor of `limine-snapper-sync`), rather than overwriting it; `omarchy-snapshot`/`limine-snapper-restore` are used as the create/restore entry points when available.
- **GUI Tweaks / Theming menu** — branches to a reduced menu (Nerd Fonts, mybash, theme picker only) instead of the full plain-Arch set.
- **Omarchy theme picker** — wraps `omarchy-theme-switcher`/`omarchy-theme-list`/`omarchy-theme-set`, an Omarchy-only menu entry.
- **GNOME Shell extensions & GUI Tools** — explicit no-ops (Omarchy replaces GNOME Shell entirely with Quickshell).
- **Terminal font configuration** — explicit no-op (Omarchy uses its own Quickshell-based terminal theming, not GNOME Terminal/gsettings).
- **Screenshot hotkey binding** — explicit no-op (Omarchy has its own `omarchy-capture-*` tooling and keybindings).
- **GNOME App Folders** — explicit no-op everywhere, with a message pointing at Omarchy's own fuzzy-search app launcher (Super+Space) instead.
- **Gaming** — informational note only; Omarchy's own on-demand installers (`omarchy-install-gaming-steam`, etc.) don't conflict with this category, they're just redundant if you've already used them.
- **Package updates** — `update_packages()` never runs a raw `pacman -Syu` on Omarchy, respecting its pre-transaction sync-guard hook; you're pointed at `omarchy update` instead.
- **BlackArch / Chaotic-AUR** — both carry an *additional* Omarchy-specific warning in their confirmation prompts about layering an uncurated repo on top of Omarchy's curated package set.

---

### 🔒 Arch Security Notes

- **AUR trust model:** AUR packages are user-submitted `PKGBUILD`s that compile from source and can run arbitrary code during the build (`makepkg`) and via post-install hooks — there is no Arch-team review comparable to the official repos. This script's `package_exists`/`aur_install` gate what gets *attempted*, not what the build itself does; you're trusting each AUR maintainer individually, same as running `yay -S` yourself.
- **Temporary passwordless-sudo grant:** scoped to `NOPASSWD: /usr/bin/pacman` only (not a blanket `NOPASSWD: ALL`), validated with `visudo -c` before being written, and removed via `trap` on exit regardless of how the script terminates — but it does exist as a real, if narrow, privilege-escalation window for the duration of AUR installs.
- **BlackArch / Chaotic-AUR:** both are large, uncurated third-party repos carrying real dependency/version-churn risk and their own signing-key trust chain — both are opt-in with an explicit confirmation dialog, and BlackArch additionally asks you to manually verify `strap.sh`'s SHA1 against blackarch.org's published value rather than trusting a hardcoded checksum that would go stale.
- **Remote install scripts run as root, trusted over HTTPS only:** Ollama, Claude Code, Mistral Vibe CLI, OpenCode, and rustup's official installers — same trust model as the Ubuntu/Fedora scripts. Claude Code, Vibe, OpenCode, and rustup specifically run **as your user** (via `su - $SUDO_USER`), not root.
- **NVIDIA proprietary driver:** a real out-of-tree DKMS kernel module, signed for Secure Boot only if you complete MOK enrollment yourself (the script prints the exact commands but can't automate the reboot-into-firmware step).
- **Docker/libvirt group = root-equivalent:** same caveat as Ubuntu/Fedora — group membership grants effective root over that daemon's socket.
- **No secrets handled:** the script never asks for or stores passwords/tokens beyond the sudoers drop-in described above, and menu input (a single character) can't reach a shell.

---

### ⚠️ Arch Known Limitations

- **AUR build times:** AUR installs compile from source via `makepkg`/`yay` rather than pulling a prebuilt binary, so individual packages (VS Code, Cursor, most browsers, Spotify, Slack, TeamViewer, 1Password, several security tools) can be noticeably slower than the Ubuntu/Fedora equivalents — especially with Chaotic-AUR not enabled.
- **yay bootstrap requirements:** needs a real non-root `SUDO_USER` session (fails gracefully with a warning otherwise) and network access to `aur.archlinux.org`.
- **Manjaro compatibility risk:** combining Manjaro's intentionally-delayed package branch with this script's AUR-heavy automatic flow is a known way to hit mismatched glibc/library-version breakage — the script gates this with a hard confirmation prompt rather than blocking outright, but the risk is real, not hypothetical.
- **Individual package-confidence caveats**, called out in the script's own comments: `whatweb`/`wfuzz` (Python 3.13 build issues / possible AUR removal), `steghide` (unresolved libjpeg-turbo AUR build issue), `sleuthkit` (only the `-git` AUR variant exists), `nomacs` (broken AUR dependency on a nonexistent `quazip-qt6`, worked around by substituting `qimgv`), Pitivi (low upstream activity, fragile AUR fallback), TeamViewer/1Password (no formal AUR maintenance/vendor-support guarantee).
- **BlackArch/Chaotic-AUR trust trade-off:** both meaningfully expand your system's trusted-signing-key surface and third-party dependency churn — see [Security Notes](#-arch-security-notes) above.
- **Omarchy update-guard interaction:** any pacman.conf change that needs a fresh sync (enabling `[multilib]` or `[chaotic-aur]`) is left un-synced on Omarchy with an instruction to run `omarchy update` afterward, since the script never runs `-Syu` itself there.
- **Package-name confidence varies by category**, same as Fedora — the harder/AUR-dependent categories were individually researched against archlinux.org/packages and aur.archlinux.org during development; ordinary official-repo packages rely on the `package_exists` safety net rather than a pre-verified list against a live system.

---

### ⚙️ Arch Customization

#### Adding New Packages (Arch)

```bash
batch_install "Category Name" \
    package1 \
    package2 \
    package3
```

`safe_install` (called by `batch_install`) already tries the official repos first and falls back to the AUR automatically — you don't need to pre-decide which tier a new package belongs to.

**Important:** verify new packages exist (`pacman -Si <pkg>` for official repos, `yay -Si <pkg>` for AUR) before adding them.

#### Creating New Categories (Arch)

1. Add an install function:
   ```bash
   install_my_category() {
       batch_install "My Category" package1 package2
   }
   ```
2. Add a menu line in `show_main_menu`.
3. Add a case branch in `main()`:
   ```bash
   31) reset_tracking; install_my_category; display_summary; prompt_menu_category "My Category" "icon" "Comment" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
   ```
4. Optionally add the new function to the `A`/`B`/`C` bulk chains in `main()`.

---

### 🐛 Arch Troubleshooting

| Issue | Solution |
| --- | --- |
| **Script exits immediately** | Run with `sudo` |
| **"Not in repos or AUR"** | The package name may be wrong, or genuinely doesn't exist for Arch — check `pacman -Si <pkg>` and `yay -Si <pkg>` manually |
| **AUR install fails / "terminal is needed to read the password"** | Should be handled automatically by the temporary passwordless-sudo grant — if you still hit this, check `/etc/sudoers.d/99-postinstall-aur-<user>` was actually written and removed cleanly; re-run the script |
| **`yay` never got installed** | Needs a real non-root `SUDO_USER` — running the script as raw `root` (not via `sudo` from a user login) skips AUR bootstrap entirely by design |
| **Raw `pacman -Syu` refuses to run / mentions a pre-transaction hook** | You're on Omarchy — use `omarchy update` instead; this script deliberately never runs a raw full-sync there |
| **NVIDIA driver installed but the module won't load** | Check Secure Boot: `mokutil --sb-state`. If enabled, enroll the MOK key manually — see the exact commands the script prints, or [Arch: Drivers & Extra Repos](#arch-drivers--extra-repos) above |
| **App folder not created** | Expected on Omarchy/Hyprland (no GNOME session exists to target) — on plain Arch, needs an active GNOME desktop session as the target user |
| **Manjaro: dependency/version conflicts after running this script** | This is the known risk flagged in the script's own Manjaro confirmation gate — Manjaro's delayed package branch and this script's AUR-heavy flow can genuinely clash; consider using Manjaro's own pamac/GUI tools for anything AUR-related instead |

#### Checking Arch Logs

```bash
# View a specific log
cat /var/log/arch_post_install_*.log

# Tail the most recent
ls -lt /var/log/arch_post_install_*.log | head -1 | awk '{print $NF}' | xargs cat
```

---

# 🎨 i3 + Catppuccin Rice Script (Fedora)

### 🚀 i3 Script Overview

[`fedroa-setup-i3-cattpuccin.sh`](fedroa-setup-i3-cattpuccin.sh) is a standalone, single-purpose script — separate from `post-install-fedora.sh` above — that builds a complete **Catppuccin Mocha–themed i3 tiling window manager** desktop on Fedora: gapped tiling, picom blur/shadows/rounded corners, a per-monitor polybar status bar, rofi launcher, dunst notifications, kitty terminal, and a full keybinding set covering window management, media/volume/brightness, screenshots, locking, power, and multi-monitor control. It's meant to be run once on a fresh Fedora install (or after `post-install-fedora.sh`) to go from "bare X11" to "usable themed i3 session."

It targets **Fedora only** (checks for `dnf` at startup and aborts otherwise) and is **idempotent-ish**: safe to re-run, but it *overwrites* every config file it manages (`~/.config/i3`, `picom`, `polybar`, `rofi`, `dunst`, `kitty`, `fastfetch`, `autorandr/postswitch`) without prompting — back up your own dotfiles first if you've customized any of them.

---

### 📦 What Gets Installed

**Core stack:** `xorg-x11-server-Xorg`, `xorg-x11-xinit`, `xorg-x11-xauth`, `xrandr`, `xset`, `i3`, `i3lock`, `picom`, `polybar`, `rofi`, `dunst`, `kitty`, `feh`

**Session/tray helpers:** `xss-lock`, `network-manager-applet`, `pasystray`, `blueman`, `lxqt-policykit`, `pipewire-pulseaudio`

**Utilities:** `lxappearance`, `papirus-icon-theme`, `fastfetch`, `git`, `curl`, `unzip`, `jq`, `flameshot`, `ImageMagick`, `brightnessctl`, `playerctl`, `numlockx`, `dex-autostart`, `autorandr`, `arandr`, `jetbrains-mono-fonts`

**i3lock-color** (COPR `tokariew/i3lock-color`) — a colorized fork of i3lock used for the themed lock screen. The COPR enable/install is best-effort: if it fails for any reason (repo down, arch mismatch), the script falls back to the plain `i3lock` it already installed unconditionally, and `lock.sh` detects at runtime which binary is actually present so the lock screen never silently breaks either way.

**JetBrainsMono Nerd Font** — the patched build (with glyph icons for polybar/rofi/i3) isn't in Fedora's repos, so it's downloaded directly from [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts) releases into `~/.local/share/fonts`. Best-effort: a failed download just logs a warning and skips it — it doesn't abort the rest of the script.

Also adds the invoking user to the **`video`** group (required for `brightnessctl` to write `/sys/class/backlight` without root) — takes effect on next login.

---

### 📥 i3 Script Installation & Usage

```bash
chmod +x fedroa-setup-i3-cattpuccin.sh
sudo ./fedroa-setup-i3-cattpuccin.sh
```

After it finishes:

1. Log out.
2. At the GDM login screen, click the gear icon next to the password field and select **i3** (installing the `i3` package registers the session automatically).
3. First login looks bare for a couple of seconds until picom/polybar spawn. If polybar doesn't appear, run `polybar -c ~/.config/polybar/config.ini top` from a kitty terminal (`Mod+Return`) to see errors directly.
4. Brightness keys need the `video` group membership added above — log out/in (or reboot) once for that to take effect.
5. For multi-monitor, see [Multi-Monitor Setup](#️-multi-monitor-setup) below.

---

### ⌨️ Keybinding Cheat Sheet

`Mod` = Super/Windows key.

| Binding | Action |
| --- | --- |
| `Mod+Return` | Open kitty |
| `Mod+d` / `Mod+shift+d` | Rofi app launcher (`drun`) / run launcher |
| `Mod+l` | Lock screen |
| `Mod+shift+p` | Power menu (lock / suspend / logout / reboot / shutdown) |
| `Print` | Screenshot (`flameshot gui`, falls back to `import`) |
| `Mod+shift+q` | Close focused window |
| `Mod+f` | Fullscreen toggle |
| `Mod+shift+space` | Floating toggle |
| `Mod+space` | Toggle tiling/floating focus |
| `Mod+h/j/k/;` | Focus left/down/up/right |
| `Mod+shift+h/j/k/;` | Move window left/down/up/right |
| `Mod+ctrl+h/l` | Focus next/prev **monitor** |
| `Mod+ctrl+shift+h/l` | Move workspace to next/prev **monitor** |
| `Mod+1..5` / `Mod+shift+1..5` | Switch to / move window to workspace 1–5 |
| `Mod+r` | Resize mode (`h/j/k/l` to resize, `Return`/`Escape` to exit) |
| `Mod+shift+r` / `Mod+shift+c` | Restart / reload i3 |
| `Mod+shift+e` | Exit i3 (with confirm) |
| `XF86Audio{Raise,Lower,Mute}Volume` | Volume via `pactl` |
| `XF86MonBrightness{Up,Down}` | Brightness via `brightnessctl` |
| `XF86Audio{Play,Next,Prev}` | Media control via `playerctl` |

---

### 🖥️ Multi-Monitor Setup

The script wires up per-monitor polybar, per-monitor wallpaper, and hotplug handling out of the box:

1. Plug in your monitor(s), run `arandr` to drag them into the layout you want (position, orientation, primary), then save it: `autorandr --save mylayout`.
2. From then on, **autorandr** auto-detects that saved layout (or any other known layout) whenever the monitor set changes and re-applies it automatically.
3. Its `~/.config/autorandr/postswitch` hook (installed by the script) re-runs two helper scripts on every profile change:
   - `~/.local/bin/polybar-launch.sh` — kills any existing polybar instance(s) and launches one fresh instance **per connected output** (`polybar --list-monitors`), so every monitor gets its own bar instead of just the primary one.
   - `~/.local/bin/wallpaper.sh` — feh normally stretches a single wallpaper across the *entire combined* virtual screen; this repeats the same image once per connected output so each monitor gets its own independent fill instead of one stretched panorama.
4. `Mod+ctrl+h/l` and `Mod+ctrl+shift+h/l` move focus/workspaces between outputs (see cheat sheet above).

---

### 🛟 Rollback Safety Net

Before touching anything, the script checks for **Btrfs + an existing snapper `root` config** (which Fedora's Btrfs-by-default installer sets up automatically on recent releases). If found, it takes a snapshot (`snapper -c root create --type single`) and prints the exact rollback command:

```bash
sudo snapper -c root undochange <snapshot-number>..0
```

This is best-effort and never blocks the rest of the script — if snapper isn't installed or there's no `root` config, it logs a warning and proceeds without a rollback point.

---

### ⚠️ i3 Script Known Limitations & Caveats

- **Systray is single-owner.** With one polybar instance per monitor, only whichever instance wins the X11 systray selection (usually the first one launched) actually shows tray icons — the others render everything except the tray module. This is an inherent X11 protocol limit, not a bug.
- **Idle-lock timing is fixed.** `xset s 300 dpms 300 600 900` locks the screen (via `xss-lock`) at 5 minutes idle, with the display standing by/suspending/powering off at 5/10/15 minutes — edit that line in the generated `~/.config/i3/config` if you want different timings.
- **`dex-autostart -a -e i3` runs third-party autostart entries** (from `~/.config/autostart` and `/etc/xdg/autostart`) alongside the script's own explicit `exec` lines for `nm-applet`/`pasystray`/`blueman-applet`/the polkit agent. In the unlikely event a package ships its own autostart `.desktop` entry for one of those same apps *without* an `OnlyShowIn=` restriction that excludes i3, you could see a duplicate tray icon until the next reload. (`lxqt-policykit`'s own autostart entry is `OnlyShowIn=LXQt;`, so it's never double-launched — the script's explicit `exec` is the only thing that starts it under i3.)
- **`polkit-gnome` was removed from Fedora 41+** (upstream stopped shipping it); the script uses **`lxqt-policykit`** instead, which provides the same authentication-agent role via `/usr/libexec/lxqt-policykit-agent`.
- **NVIDIA users:** picom defaults to the `glx` backend (comment in `~/.config/picom/picom.conf` notes this is tuned for Mesa/Intel/AMD) — switch it to `xrender` if you see tearing or flicker on the proprietary NVIDIA driver.
- Every config file this script manages is **overwritten on re-run** with no automatic backup — if you've hand-edited any of them, copy them aside first.

---

## 📜 License

All scripts in this repo are provided **as-is** without warranty. You are free to:

- Use them for personal or commercial purposes
- Modify and distribute them
- Use them as a base for your own scripts

**Attribution:**

- If you share modified versions, please credit the original source
- Some packages have their own licenses (check individual package terms) — see especially the DVD-decryption note under [Known Limitations](#️-known-limitations)

---

## 🙏 Acknowledgments

- **Ubuntu Community**, **Fedora Community**, and **Arch Linux Community**: For the excellent package repositories
- **[Omarchy](https://omarchy.org) / Basecamp**: For the opinionated Hyprland-based Arch distro the Arch script detects and defers to
- **Arch Linux AUR maintainers** and the **[yay](https://github.com/Jguer/yay)** project: For making the AUR usable as an automated fallback layer
- **BlackArch Linux** and **[Chaotic-AUR](https://aur.chaotic.cx/)**: For the opt-in security-tooling and prebuilt-AUR-binary repos the Arch script can bootstrap
- **Chris Titus Tech**: For the mybash configuration
- **Ollama**: For making local LLMs accessible
- **Mistral AI**: For Vibe and open-source AI models
- **Genymobile**: For scrcpy
- **RPM Fusion**: For proprietary codecs and drivers on Fedora
- **Fyra Labs / Ultramarine Linux**: For the Terra repo
- **[vinceliuice](https://github.com/vinceliuice)**: For the Graphite GTK theme and the Qogir, WhiteSur, and Vimix icon themes
- **[Fausto-Korpsvart](https://github.com/Fausto-Korpsvart)**: For the Catppuccin, Everforest, Gruvbox, Kanagawa, Material, Nightfox, Osaka, Rosé Pine, and Tokyonight GTK themes
- **[JustDeax](https://github.com/JustDeax)**: For the Obsidian Flow shell theme
- **[metro2222](https://github.com/metro2222)**: For the Oval and Rounded Rectangle Dark Blue shell themes
- **[cbrnix](https://github.com/cbrnix)**: For the Newaita icon theme
- **[PixlOne](https://github.com/PixlOne)**: For Logiops, the Logitech HID++ driver the Arch and Ubuntu scripts can build from source
- **[aaddrick](https://github.com/aaddrick)**: For the Claude Desktop Linux repackaging project
- **All package maintainers**: For their hard work on the included software

---

*Last updated: August 25, 2026*
