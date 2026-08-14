# Ubuntu 26.04 LTS / 26.10 Post-Install Script

> **Menu-driven post-installation script with verified packages, error handling, installation checks, and automatic GNOME Shell app-folder creation — supports both Ubuntu 26.04 LTS and 26.10**
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
  - [Security Tools](#security-tools)
  - [.NET Development](#net-development)
  - [DevOps &amp; Cloud](#devops--cloud)
  - [Desktop Apps](#desktop-apps)
- [🔀 Bulk Options (A / B / C)](#-bulk-options-a--b--c)
- [🔧 Error Handling &amp; Installation Checks](#-error-handling--installation-checks)
- [📊 Installation Summary &amp; Logging](#-installation-summary--logging)
- [🔒 Security Notes](#-security-notes)
- [⚠️ Known Limitations](#️-known-limitations)
- [⚙️ Customization](#-customization)
- [🐛 Troubleshooting](#-troubleshooting)
- [📜 License](#-license)

---

## 🚀 Overview

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

## ✨ Features

### Core Features

| Feature                       | Description                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| **Version Detection**         | Detects the running release at startup, supports **Ubuntu 26.04 LTS and 26.10**, warns/prompts on anything else |
| **Nala Front-End**            | Installs and uses [Nala](https://github.com/volitank/nala) for installs/updates (parallel downloads, cleaner output); transparently falls back to apt-get if unavailable |
| **Catppuccin-Themed Output**  | Menus, logs, and summary use the Catppuccin Mocha palette (truecolor), auto-disabled for non-TTY / `NO_COLOR` |
| **Interactive Menu**          | Text-based menu with 28 categories (plus Ubuntu Studio and Security sub-menus)                 |
| **GNOME App-Folder Creation** | After each category, optionally groups the apps you just installed into a Super-key app folder |
| **Terminal Font Setup**       | In GUI Tweaks, optionally sets the terminal / system monospace font to an installed Nerd Font (works on Ptyxis, GNOME Console, and gnome-terminal) |
| **Error Handling**             | Skips unavailable packages, continues installation                                              |
| **Pre-Install Checks**        | Verifies if packages are already installed                                                      |
| **Package Verification**      | Checks if packages exist in repositories before attempting                                      |
| **Snap Fallback**              | Installs archive-gap tools (LXD, IntelliJ, DBeaver CE) via snap with the same tracking as apt   |
| **Installation Tracking**     | Tracks installed, skipped, and failed packages per run                                          |
| **Summary Reporting**          | Shows detailed installation summary with the "S" command                                        |
| **Log Saving**                 | Saves complete logs to `/var/log/ubuntu_post_install_TIMESTAMP.log`                             |

### Statistics

- **Main Menu Categories:** 28 (plus Ubuntu Studio and Security sub-menus)
- **Package Front-End:** Nala (auto-installed, with transparent apt-get fallback)
- **Verified APT Packages:** 200+
- **Snap-Only Tools:** 3 (LXD, IntelliJ IDEA Community, DBeaver CE)
- **Third-Party Direct-Install Tools:** VS Code, Sublime Text, Ollama, Cursor, Mistral Vibe CLI, Claude Code, Gemini CLI, OpenCode, Go, Rust/rustup, Chris Titus mybash, Azure CLI, lazygit (via Go), LazyVim + Nordic (Neovim config)
- **Estimated Install Time:** 15 minutes – several hours (depending on selections; "Install EVERYTHING" is a long run)
- **Estimated Disk Space:** 5–30GB+ (depending on selections)

---

## 📥 Installation

### Prerequisites

- **Ubuntu 26.04 LTS or 26.10** (the script detects the release at startup; on any other version it warns and asks whether to continue)
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

1. **Main Menu**: Shows all 28 categories (`0`–`28`)
2. **Sub-Menus**: Ubuntu Studio (option `1`) has a sub-menu (`1`–`6`); Security Tools (option `25`) has a sub-menu to choose Full or Defensive-only; GUI Tweaks (option `22`), Browsers (option `29`), and Communication (option `30`) each have a sub-menu to install everything in the category or pick a single item
3. **Bulk Options**: `A`, `B`, `C` (see [Bulk Options](#-bulk-options-a--b--c) below)
4. **`S`** — Show Installation Summary
5. **`0`** — Exit

After a single category finishes installing, you'll be asked whether to group its apps into a GNOME app folder. Bulk options (`A`/`B`/`C`) **auto-create** a folder per category as they go — no prompts (fitting their hands-off nature).

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

**Raster/Vector Editors:** `gimp`, `inkscape`, `krita`, `darktable`, `rawtherapee`, `shotwell`, `nomacs`

**3D:** `blender`

**Pinta** — apt's `pinta` was dropped from Ubuntu's repos along with Mono; installed from Flathub (`com.github.PintaProject.Pinta`) instead when the apt package isn't available, same fallback pattern as Telegram.

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
- **`ubuntu-restricted-extras` (opt-in prompt):** extra patent-encumbered codecs (MP3/H.264 helpers) plus Microsoft core fonts. It's kept out of the default codec batch because its `ttf-mscorefonts-installer` dependency gates on an interactive **Microsoft core-fonts EULA** that would hang an unattended install. `install_restricted_extras` therefore **asks first** — the prompt states that choosing Yes accepts that EULA — and only then preseeds the answer (`debconf-set-selections`) so the install runs non-interactively. Declining is recorded as **skipped**, not failed. This prompt appears at the end of the Video category, including within the `B`/`C` bulk runs.

---

### Audio Production

**DAWs & Editors:** `audacity`, `ardour`, `lmms`, `musescore`, `hydrogen`

**Synth:** `zynaddsubfx` — ships four separate launchers (Alsa / Jack / Jack multi-channel / Oss), all added to the app folder

**JACK Audio:** `qjackctl`, `jackd2`, `pulseaudio-module-jack`, `xjadeo` (JACK video monitor)

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

**LazyVim + Nordic (optional prompt):** after the editors install, you're asked whether to set up [LazyVim](https://github.com/LazyVim/starter) as your Neovim config with the [Nordic](https://github.com/AlexvZyl/nordic.nvim) theme. It's a **prompted opt-in** because it **replaces `~/.config/nvim`** — any existing config is backed up to `~/.config/nvim.bak.<timestamp>` first. The clone runs as your user; plugins sync on the first `nvim` launch. The prompt also appears in the `A`/`C` bulk runs.

---

### Python Development

`python3`, `python3-dev`, `python3-venv`, `python3-pip`, `python-is-python3`, `ipython3`, `pipx`

---

### Web Development

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

### Java Development

**JDK/JRE & Build Tools:** `default-jdk`, `default-jre`, `gradle`, `maven`, `ant`

**Testing:** `junit4`, `testng`

**Environment:** `JAVA_HOME` is detected and set two ways — a bare `JAVA_HOME=…` line in `/etc/environment` (system-wide, idempotently rewritten) and a `/etc/profile.d/java-home.sh` that exports it and adds `$JAVA_HOME/bin` to `PATH` at login. **Note:** `/etc/environment` is a plain `NAME=value` file, **not** a shell script — earlier versions wrote `export JAVA_HOME=…` there, which breaks any dpkg maintainer script that reads the file (e.g. `install-info`) with `export: … bad variable name` and then fails every later package. The current code writes the correct format and the detection step also strips any malformed `export` lines a previous run left behind.

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

**Direct Install (if `go` isn't already on `PATH`):** downloads and installs **Go 1.22.5** from the official source to `/usr/local/go`, and adds it to `PATH` via **`/etc/profile.d/go.sh`** (a real shell script that expands `$PATH` at login — *not* `/etc/environment`, which is a `NAME=value` pam_env file where an `export` line would break `install-info`; the step also strips any such broken line an older version left behind)

---

### Rust Development

**APT Packages:** `rustc`, `cargo`

**Direct Install (if `rustup` isn't already present):** installs **rustup** from the official source **as the desktop user** (so the toolchain lands in *their* `~/.cargo`, not root's), sets `stable` as default, and adds the `rust-src` component. Skipped when there's no sudo-invoking user (script run as root directly).

---

### Node.js Development

Calls the same Node.js installer used by [Web Development](#web-development) — NodeSource repository, Node.js 20.x, plus the same global npm package set. This overlap with Web Development is intentional (kept per an earlier explicit decision), not an accidental duplicate.

---

### PHP Development

**Note:** the Ondrej PHP PPA is **not yet available for Ubuntu 26.10** — this category uses the **default Ubuntu repository PHP packages only**.

`php-cli`, `php-fpm`, `php-dev`, `php-pear`, `php-mysql`, `php-pgsql`, `php-sqlite3`, `php-gd`, `php-curl`, `php-mbstring`, `php-xml`, `php-zip`, `composer`

> As in Web Development, the bare `php` metapackage is omitted so it can't pull `libapache2-mod-php` and restart Apache into a port-80 conflict (relevant when apache2 is already installed, e.g. during an "EVERYTHING" run). The same apache-autostart guard is applied here as a safety net.

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
| **Alpaca**           | Flathub (`com.jeffser.Alpaca`) | Native GTK4 GUI client for Ollama                |
| **Claude Code**     | Official native installer (`claude.ai/install.sh`), npm fallback | Anthropic's CLI code assistant (provides the `claude` command) |
| **Gemini CLI**       | `npm install -g @google/gemini-cli` | Google's official CLI code assistant (provides the `gemini` command) |
| **Mistral Vibe CLI** | Official installer script (`mistral.ai/vibe/install.sh`), installs the `mistral-vibe` Python package via `uv`/`pip` | Mistral's terminal coding agent (provides the `vibe` command) |
| **OpenCode**         | Official native installer (`opencode.ai/install`), npm fallback (`opencode-ai`) | Provider-agnostic terminal AI coding agent (provides the `opencode` command) |
| **Cursor**           | `.deb` download       | AI-powered code editor                                    |

All of these register in the installed/skipped/failed tracking, so they appear in the summary and are fed to the app-folder resolver. **Cursor** ships its own `cursor.desktop` and **Alpaca** exports a Flatpak launcher, so both are grouped into the AI Tools folder. **Ollama**, **Claude Code**, **Gemini CLI**, **Mistral Vibe CLI**, and **OpenCode** are command-line only (no launcher), so they're tracked but don't get a folder icon — expected, same as `docker`/`adb`.

---

### GUI Tweaks

Option `22` has its own sub-menu so you can install everything below at once, or pick just one piece (e.g. only **Themes**) instead of the full bundle: **All GUI Tweaks**, **Icon Sets**, **Themes**, **Cursor Themes**, **Nerd Fonts**, **Chris Titus mybash**, **GUI Tools**, **GNOME Shell Extensions**.

**Icon Sets:** (creators credited in [Acknowledgments](#-acknowledgments))

- **Apt packages** (Papirus via its Team PPA; the rest are plain universe packages): `papirus-icon-theme`, `numix-icon-theme`, `numix-icon-theme-circle`, `breeze-icon-theme`, `adwaita-icon-theme`, `obsidian-icon-theme`
- **Built from source, straight to `/usr/share/icons`** (no PPA/package exists for these): [Qogir](https://github.com/vinceliuice/Qogir-icon-theme), [WhiteSur](https://github.com/vinceliuice/WhiteSur-icon-theme), [Vimix](https://github.com/vinceliuice/Vimix-icon-theme) — each cloned and run through its own `install.sh` directly as root (their destination logic is already `$UID`-aware and has no other per-user dependency, unlike the GTK themes below, so no `su`-as-desktop-user dance is needed here). Tracked via a system-wide marker file under `/var/lib/ubuntu-postinstall-themes/`.
- **Ready-made, no build step**: [Newaita](https://github.com/cbrnix/Newaita) (light + dark) — copied straight into `/usr/share/icons`.

> The Papirus PPA is added through a codename-aware helper (`add_ppa`). PPAs are keyed by codename: the 26.04 LTS almost always has a build, while a brand-new interim release (26.10) frequently has none yet — if the PPA has no build for the running codename the helper warns and continues with the distro icon packages instead of leaving a broken apt source behind.

**GTK Theme:** `arc-theme`

**Third-party GTK/Shell themes:** Beyond the apt-packaged `arc-theme`, a curated set of popular GitHub theme projects is installed straight from source, entirely **as the logged-in desktop user** (needs an active GNOME session — skipped cleanly otherwise, same as the GNOME extensions step):

- **SASS-built GTK themes** ([Graphite](https://github.com/vinceliuice/Graphite-gtk-theme), [Catppuccin](https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme), [Everforest](https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme), [Gruvbox](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme), [Kanagawa](https://github.com/Fausto-Korpsvart/Kanagawa-GKT-Theme), [Material](https://github.com/Fausto-Korpsvart/Material-GTK-Themes), [Nightfox](https://github.com/Fausto-Korpsvart/Nightfox-GTK-Theme), [Osaka](https://github.com/Fausto-Korpsvart/Osaka-GTK-Theme), [Rosé Pine](https://github.com/Fausto-Korpsvart/Rose-Pine-GTK-Theme), [Tokyonight](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme)) — each is cloned and run through its own `install.sh` with `--libadwaita` (so GTK4/Libadwaita apps pick it up too), landing in `~/.themes`. `sassc` is installed first since every one of these installers self-elevates with an internal `sudo apt install sassc` when it's missing, which would otherwise hang waiting for a terminal. Idempotent via a per-theme sentinel file under `~/.cache/ubuntu-postinstall-themes/`, since (unlike an apt package) there's no single "is it installed" check for a theme.
- **Ready-made GNOME Shell themes** ([Oval](https://github.com/metro2222/ovel), [Rounded Rectangle Dark Blue](https://github.com/metro2222/rounded-rectangle-dark-blue-theme)) — no build step, just copied into `~/.local/share/themes/`.
- **[Obsidian Flow](https://github.com/JustDeax/Obsidian-flow-shell-theme)** — installed via its own Python installer (`install.py -a`, all accent colors/light/dark) rather than a folder copy, into `~/.themes`.

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

**GNOME Shell extensions:** installed via [`gext`](https://github.com/essembeh/gnome-extensions-cli) (set up per-user with `pipx`), as the logged-in user (needs an active GNOME session — skipped cleanly otherwise). Curated set: GSConnect, Window State Manager, Bluetooth Battery Meter, Auto Move Windows, User Themes, Clipboard History, [Dash to Dock](https://extensions.gnome.org/extension/307/dash-to-dock/). Best-effort — a failed extension is logged and skipped; some need a log-out/in to activate.

**Logiops (Logitech HID++ driver) — optional prompt:** builds [PixlOne/logiops](https://github.com/PixlOne/logiops) from source and enables the `logid` service. **Prompted opt-in** because it only matters for configurable Logitech mice/keyboards and pulls a build toolchain. Writes a working `/etc/logid.cfg` (MX Master 3 / MX Master — gestures, smartshift, hi-res scroll, DPI) **embedded in the script** so it works standalone; any existing config is backed up to `/etc/logid.cfg.bak.<timestamp>` first. Edit the config in `write_logid_config()` to change mappings.

*(`evince`/`gedit` intentionally not re-listed here — [Office & Productivity](#office--productivity) and [Code Editors](#code-editors) already own them.)*

---

### Windows Software Support

**Wine Environment:** `wine`, `winetricks`, `zenity`

> The Ubuntu `winetricks` package ships as a CLI script with **no `.desktop` launcher**, so it never got a menu icon or landed in the app folder (same reason `adb`/`docker` don't). Since winetricks has a GUI when launched with no arguments, the script now **creates a `winetricks.desktop` launcher** (if the package doesn't provide one) so it appears in menus and is grouped into the Windows Software Support folder. `zenity` is installed so that GUI can draw its dialogs.

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

### Security Tools

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

### .NET Development

Installs the **.NET SDK** from Ubuntu's own repositories. Because the exact SDK versions available drift by release, the script installs the **newest `dotnet-sdk-*` actually present** (checks for `dotnet-sdk-10.0`, then `9.0`, then `8.0`) rather than hardcoding one that may have aged out, and adds the matching `aspnetcore-runtime-*` when packaged. EF Core and other `dotnet tool` installs are per-user (`dotnet tool install -g …`) and left to you.

> If no `dotnet-sdk-*` package is found on your release, it's logged as failed with a pointer to [Microsoft's Linux install docs](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu).

---

### DevOps &amp; Cloud

Developer/cloud tooling installed together:

- **Docker + docker-compose** (`docker.io`, `docker-compose`) — a lightweight, dedicated Docker install; adds the invoking user to the `docker` group and enables the service. *(The [Container & Virtualization](#container--virtualization) category also installs these, alongside podman/LXC/KVM/Cockpit — this is just Docker for a dev box.)*
- **Azure CLI** — via Microsoft's official install script (`curl -sL https://aka.ms/InstallAzureCLIDeb | bash`); provides the `az` command.
- **lazygit** — installed with `go install github.com/jesseduffield/lazygit@latest`. Go is installed first if missing; the build runs **as your user** (lands in `~/go/bin`) and is symlinked into `/usr/local/bin` so it's on everyone's `PATH`.

> `docker`/`az`/`lazygit` are CLI tools with no `.desktop` launcher, so this category produces no app-folder icons (expected).

---

### Desktop Apps

Common desktop applications:

- **Spotify** — installed from Spotify's own apt repo (`repository.spotify.com`) rather than snap, so it updates through apt; migrates off a leftover snap automatically.
- **Slack** — official `slack-desktop` `.deb` installed through the active package manager (version scraped from Slack's release notes, with a pinned fallback); migrates off a leftover snap automatically.
- **Remmina** (remote-desktop client) — installed from the upstream `remmina-next` PPA when available (codename-aware via `add_ppa`, falls back to the distro package), with the RDP (`remmina-plugin-rdp`) and secret-storage (`remmina-plugin-secret`) plugins.
- **Windows App for Linux** ([mariuszkopowski/windows-app-for-linux](https://github.com/mariuszkopowski/windows-app-for-linux)) — a remote-desktop client for Windows 365 / Azure Virtual Desktop / RDP. Not on Flathub, so the latest `x86_64` Flatpak bundle is downloaded from its GitHub releases and installed into the desktop user's per-user Flatpak scope (installs Flatpak itself first if missing).
- **TeamViewer** — official vendor `.deb` downloaded and installed directly (amd64/arm64); the package registers TeamViewer's own apt repo so future updates flow through apt.
- **1Password** — installed from [1Password's official apt repo](https://support.1password.com/install-linux/) (amd64 only); also configures the documented `debsig-verify` policy for package-integrity checks.

---

## 🔀 Bulk Options (A / B / C)

| Option | Runs                                                                                                                                                                                            | Notes                                    |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| **A**  | Code Editors, Python, Web Development, Java, C/C++, Go, Rust, Node.js, PHP, Ruby, .NET, General Development Tools, AI Tools                                                                    | "ALL Development Tools" (languages; DevOps & Cloud is C only) |
| **B**  | Ubuntu Studio (Full), Graphics, Video, Audio                                                                                                                                                    | "ALL Media Tools"                        |
| **C**  | Everything in A and B, plus Database Tools, Container & Virtualization, Gaming, Office & Productivity, System Utilities, GUI Tweaks, Windows Software Support, Android Tools, Security Tools, .NET, DevOps & Cloud, and Desktop Apps | "EVERYTHING"                             |

**App folders:** A/B/C **auto-create** a GNOME app folder for each category they install (no prompts). The individual numbered categories (1–24) and the Ubuntu Studio sub-menu instead *ask* before creating each folder. Either way, folder creation needs an active GNOME session (see [GNOME App Folders](#️-gnome-app-folders-super-key-groups)); without one, each is skipped with a warning and packages still install.

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

The install/update step itself runs through the `pm_install`/`pm_update` front-end abstraction — **Nala** when available, **apt-get** otherwise — so the checks above are identical regardless of back-end. Queries (`apt-cache`, `dpkg`) always use apt directly.

Snap-only tools (`lxd`, `intellij-idea-community`, `dbeaver-ce`) go through the equivalent `safe_snap_install` flow instead, checking `command -v`/`snap list` before falling back to `snap install`.

### Key Functions

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

### Error Recovery

- **Failed Package Lists**: Continues installation even if some packages fail
- **Dependency Fixing**: Falls back to `apt-get install -f` where relevant
- **Retry Logic**: Allows retry for `apt-get update` and npm global package installs
- **Non-Fatal Extras**: Optional extras like `libdvd-pkg`'s DVD-decryption build failing (e.g. no network path to videolan.org) don't abort the run
- **Cleanup**: Removes temporary files and apt source entries added for third-party repos (VS Code, Sublime Text) even on failure

---

## 📊 Installation Summary &amp; Logging

### Real-Time Feedback

Output is themed with the **[Catppuccin](https://github.com/catppuccin/catppuccin) Mocha** palette (24-bit truecolor), assigned by semantic role. Colors **auto-disable** when output isn't a terminal or `NO_COLOR` is set, so piped/redirected output and the log file stay plain.

- 🟢 **Green** `✓`: Success
- 🔵 **Blue** `•`: Info
- 🟡 **Yellow** `▲`: Warnings (including "Desktop file not found" for CLI-only tools — see individual category notes above for when this is expected)
- 🔴 **Red** `✗`: Errors
- 🟣 **Mauve**: headings / menu keys · **Lavender**: prompts · **Peach**: bulk actions (A/B/C)

> Best viewed in a truecolor terminal (Ptyxis, GNOME Console, most modern terminals). On a legacy 8/16-color terminal the escapes degrade to the nearest supported color.

### Summary Screen

Press `S` at any time, or it's shown automatically after each category, to see totals, and lists of failed and skipped packages.

### Log File

```
/var/log/ubuntu_post_install_TIMESTAMP.log
```

Contains a timestamp, the running user, summary statistics, and the full installed/failed package lists for that run.

---

## 🔒 Security Notes

The script runs as **root** and installs software from a mix of Ubuntu repos and third-party sources. What that means for trust:

- **Package integrity:** apt/Nala packages are signed by Ubuntu's archive keys. Third-party **apt repos** (VS Code, Sublime) pin their GPG key with `signed-by=` and import it directly into `/usr/share/keyrings/` (no `/tmp` intermediate). **PPAs** (Papirus, Remmina) trust the Launchpad PPA owner, whose packages run maintainer scripts as root.
- **Remote install scripts run as root, trusted over HTTPS only:** NodeSource (`setup_20.x`), Ollama (`install.sh`), and Azure CLI (`InstallAzureCLIDeb`) are piped to `bash`/`sh`. These are the vendors' official install methods; integrity rests on TLS + the vendor, with no independent checksum. The **Cursor `.deb`** (`dpkg -i`) is likewise TLS-trust only. **Claude Code**, **Mistral Vibe CLI**, **OpenCode** (all `install.sh`), and rustup are installed **as your user** (via `su - $SUDO_USER`), not root.
- **Docker group = root-equivalent:** installing Docker adds your user to the `docker` group, which grants full control of the Docker socket — effectively root. This is standard and expected; know that it's a privilege boundary. (Prefer rootless Docker if you want to avoid it.)
- **Third-party desktop code:** GNOME Shell extensions (from extensions.gnome.org) run in your shell as your user; `--classic` snaps (IntelliJ, DBeaver CE) run unconfined. Both execute third-party code by design.
- **Source builds:** Logiops is compiled and `make install`ed from source in a **private `mktemp -d`** (not a predictable, reusable `/tmp` path).
- **No secrets handled:** the script never asks for or stores passwords/tokens, and menu input (a single character) can't reach a shell.

---

## ⚠️ Known Limitations

- **Bulk options auto-create app folders**: `A`/`B`/`C` create a folder per category automatically via `auto_category` (no prompt). Categories whose packages have no GUI launcher (e.g. System Utilities, Android Tools) are skipped with a "no GUI apps" notice rather than producing an empty folder.
- **DVD decryption legality**: `libdvd-pkg` (in the Video category) builds `libdvdcss2` from source, which is legal in some jurisdictions and legally gray in others (this is why it's in `multiverse` rather than `main`). It's on by default; remove the `install_libdvdcss` call if you'd rather it not run.
- **`ubuntu-restricted-extras` is opt-in** in the Video category (MP3/H.264 codec helpers + Microsoft core fonts). It prompts before installing because saying yes accepts the Microsoft core-fonts EULA; decline and it's recorded as skipped. Note the prompt also appears during the `B`/`C` bulk runs (the one interactive point in an otherwise hands-off bulk install).
- **26.10 package parity is not exhaustively verified**: package names were checked against the 26.04-era archive; 26.10 shares the same names in practice, but any package renamed or dropped in the interim release simply lands in the `FAILED` list (via the existing `package_exists` guard) rather than being pre-corrected. The version dispatch (`is_lts`/codename) is in place for such cases as they surface.

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
| **"Designed for Ubuntu 26.04/26.10, detected: …"** | You're on a release the script isn't validated against — answer `y` to continue anyway, or add your version to `SUPPORTED_VERSIONS` at the top of the script |
| **Terminal font didn't change**     | Set it as your user (not `sudo`): `gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 12'`. Confirm the font is present with `fc-list \| grep -i jetbrains`. On Ptyxis, ensure "use system font" is on (the script sets it) |
| **"unit files changed on disk, run daemon-reload"** | Benign systemd notice when a package drops a unit/binfmt file (e.g. clang). Not an error — the script runs `systemctl daemon-reload` after each batch to reconcile it. Safe to ignore if it still appears once mid-batch |
| **`install-info` fails: `export: … bad variable name`** | A previous Java **or Go** install wrote `export` lines into `/etc/environment` (invalid there). Clean them and finish configuring: `sudo sed -i '/^export /d' /etc/environment && sudo dpkg --configure -a`. Current script versions no longer write those lines (Java → `/etc/profile.d/java-home.sh`, Go → `/etc/profile.d/go.sh`) and auto-strip old ones on the next run |
| **`404 Not Found` / `is not signed` on package downloads** | A `nala fetch`-selected mirror is incomplete/stale (the script no longer selects mirrors, but a prior run leaves the chosen mirrors in `/etc/apt/sources.list.d/fetch.sources`). Restore Ubuntu's defaults: `sudo rm -f /etc/apt/sources.list.d/fetch.sources && sudo nala update` |

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
- **[vinceliuice](https://github.com/vinceliuice)**: For the Graphite GTK theme and the Qogir, WhiteSur, and Vimix icon themes
- **[Fausto-Korpsvart](https://github.com/Fausto-Korpsvart)**: For the Catppuccin, Everforest, Gruvbox, Kanagawa, Material, Nightfox, Osaka, Rosé Pine, and Tokyonight GTK themes
- **[JustDeax](https://github.com/JustDeax)**: For the Obsidian Flow shell theme
- **[metro2222](https://github.com/metro2222)**: For the Oval and Rounded Rectangle Dark Blue shell themes
- **[cbrnix](https://github.com/cbrnix)**: For the Newaita icon theme
- **All package maintainers**: For their hard work on the included software

---

*Last updated: August 11, 2026*
