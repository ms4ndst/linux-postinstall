#!/usr/bin/env python3
"""Port post-install-openmandriva.sh -> post-install-mageia.sh.

Mageia and OpenMandriva share the Mandriva lineage (dnf, lib64* naming, mostly
shared package names), so the hand-maintained OpenMandriva post-install script -
which already did the Mandriva-ification (dnf5 front-end, lib64 renames, the
tig/vnstat/greenshot/logiops source builds) - is the closest base. This port
changes only what differs between the two Mandriva distros:

  - Repo model: OpenMandriva's repo-tree (cooker/rolling/rock) + subrepos
    (extra | restricted | non-free) -> Mageia cauldron + media (core | nonfree |
    tainted). The call interface (`enable_om_repo restricted` etc.) is kept
    intact; only the function bodies change, mapping restricted->tainted,
    non-free->nonfree, and extra->core (always-on, a no-op) against the
    cauldron-<arch>-<media> repo ids.
  - NVIDIA: OpenMandriva's prebuilt open kmods (nvidia + nvidia-kmod-open-
    desktop) -> Mageia's DKMS driver from nonfree (dkms-nvidia-current +
    nvidia-current + x11-driver-video-nvidia-current). Exact package is GPU/
    release-dependent, so it's best-effort with a `dnf search dkms-nvidia` hint.
  - Release gate: accept id=mageia / cauldron instead of OpenMandriva 5.0/6.0.
  - Prose: "OpenMandriva" -> "Mageia" globally; the title, the honesty note, the
    NVIDIA section header and the ROME-rolling labels are rewritten specifically.

Chained port: run after the OpenMandriva post-install script is current (it is
the source). Every step anchors on a unique string; a stale anchor warns.

NOTE: best-effort and UNTESTED on a real Mageia box at authoring time. The repo
ids, NVIDIA packages and any Mageia-vs-OM package delta may need a one-line fix
after the first run; strict installs + package_exists() skip unknown names.

Usage: python3 -I port_mageia_postinstall.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
SRC = ROOT / "post-install-openmandriva.sh"
DST = ROOT / "post-install-mageia.sh"


def main():
    if not SRC.is_file():
        sys.exit(f"ERROR: {SRC} not found.")
    out = SRC.read_text(encoding="utf-8")
    warnings = []

    def sub(old, new, why="", count=1):
        nonlocal out
        if old not in out:
            warnings.append(f"stale anchor ({why or old[:50]!r})")
            return
        out = out.replace(old, new, count)

    # ---- 1. Title + honesty note -------------------------------------------
    sub(
        "# OpenMandriva Lx Post-Install Script v1 (dnf5)\n"
        "# Menu-driven installer with error handling - OpenMandriva port of post-install-fedora.sh",
        "# Mageia Post-Install Script v1 (dnf5, cauldron)\n"
        "# Menu-driven installer with error handling - Mageia port of post-install-openmandriva.sh.\n"
        "# BEST-EFFORT / UNTESTED on a real Mageia box: ported from the OpenMandriva script\n"
        "# (shared Mandriva lineage), repo setup remapped to cauldron nonfree/tainted and\n"
        "# NVIDIA/codec packages adjusted to Mageia names. Deltas may need a one-line fix.",
        why="title",
    )

    # ---- 2. om_probe_enabled / enable_om_repo: .repo glob -------------------
    out = out.replace("/etc/yum.repos.d/openmandriva-*.repo", "/etc/yum.repos.d/*.repo")

    # ---- 3. detect_repo_tree -> cauldron -----------------------------------
    sub(
        '''detect_repo_tree() {
    OM_REPO_TREE=""
    local tree
    for tree in cooker rolling rock release "${OM_VERSION:-}"; do
        [ -n "$tree" ] || continue
        if om_probe_enabled "${tree}-${OM_ARCH}"; then
            OM_REPO_TREE="$tree"; return 0
        fi
    done
    return 1
}''',
        '''detect_repo_tree() {
    # Mageia: this rice targets the cauldron (rolling) tree.
    OM_REPO_TREE="cauldron"; return 0
}''',
        why="detect_repo_tree",
    )

    # ---- 4. check_version: accept Mageia -----------------------------------
    sub(
        '''    if [ "${OM_ID:-}" = "openmandriva" ]; then
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
    fi''',
        '''    if [ "${OM_ID:-}" = "mageia" ]; then
        supported=true
    fi
    if $supported; then
        log INFO "Detected Mageia ${OM_VERSION:-cauldron} (repo tree: ${OM_REPO_TREE:-cauldron})"
    else
        log WARNING "Designed for Mageia cauldron (id=mageia), detected: ${OM_ID:-unknown} ${OM_VERSION:-unknown}"
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi''',
        why="check_version",
    )

    # ---- 5. om_repo_enabled + mga_sub --------------------------------------
    sub(
        '''om_repo_enabled() {
    local sub="$1"
    [ -z "${OM_REPO_TREE:-}" ] && detect_version
    if [ -z "${OM_REPO_TREE:-}" ] || [ -z "${OM_ARCH:-}" ]; then return 1; fi
    om_probe_enabled "${OM_REPO_TREE}-${OM_ARCH}-${sub}"
}''',
        '''# Map an OM subrepo name to Mageia's cauldron media: OM 'restricted' (codecs)
# -> Mageia 'tainted', OM 'non-free' -> Mageia 'nonfree', OM 'extra' (community)
# -> Mageia 'core' (always enabled; empty = nothing to flip).
mga_sub() {
    case "$1" in
        non-free|nonfree)   echo "nonfree" ;;
        restricted|tainted) echo "tainted" ;;
        extra|core|"")      echo "" ;;
        *)                  echo "$1" ;;
    esac
}

om_repo_enabled() {
    local sub; sub="$(mga_sub "$1")"
    [ -z "$sub" ] && return 0            # core: always enabled
    [ -z "${OM_ARCH:-}" ] && detect_version
    [ -z "${OM_ARCH:-}" ] && return 1
    om_probe_enabled "cauldron-${OM_ARCH}-${sub}"
}''',
        why="om_repo_enabled",
    )

    # ---- 6. enable_om_repo -------------------------------------------------
    sub(
        '''enable_om_repo() {
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
    for f in /etc/yum.repos.d/*.repo; do
        [ -f "$f" ] || continue
        if grep -q "^\\[$repoid\\]" "$f" 2>/dev/null; then
            if awk -v id="[$repoid]" '
                /^\\[/ { inrepo = ($0 == id); print; next }
                inrepo && /^enabled[[:space:]]*=/ { print "enabled=1"; next }
                { print }
            ' "$f" > "$f.omnew" && mv "$f.omnew" "$f"; then
                return 0
            fi
            rm -f "$f.omnew"
        fi
    done
    log WARNING "Could not enable '$repoid' - check /etc/yum.repos.d/*.repo"
    return 1
}''',
        '''enable_om_repo() {
    local sub; sub="$(mga_sub "$1")"
    [ -z "$sub" ] && return 0            # core: always enabled
    [ -z "${OM_ARCH:-}" ] && detect_version
    if [ -z "${OM_ARCH:-}" ]; then
        log WARNING "Could not detect the arch - enable '$1' manually in /etc/yum.repos.d/"
        return 1
    fi
    local repoid="cauldron-${OM_ARCH}-${sub}"
    om_probe_enabled "$repoid" && return 0
    dnf config-manager setopt "$repoid.enabled=1" &>/dev/null && return 0
    dnf config-manager --set-enabled "$repoid" &>/dev/null && return 0
    # last resort: flip the stanza in the shipped .repo file directly.
    local f
    for f in /etc/yum.repos.d/*.repo; do
        [ -f "$f" ] || continue
        if grep -q "^\\[$repoid\\]" "$f" 2>/dev/null; then
            if awk -v id="[$repoid]" '
                /^\\[/ { inrepo = ($0 == id); print; next }
                inrepo && /^enabled[[:space:]]*=/ { print "enabled=1"; next }
                { print }
            ' "$f" > "$f.mganew" && mv "$f.mganew" "$f"; then
                return 0
            fi
            rm -f "$f.mganew"
        fi
    done
    log WARNING "Could not enable '$repoid' - check /etc/yum.repos.d/*.repo"
    return 1
}''',
        why="enable_om_repo",
    )

    # ---- 7. bootstrap_repos: install cauldron repo defs + Mageia wording ----
    sub(
        '    log INFO "Enabling OpenMandriva extra + restricted + non-free repos..."',
        "    # Make sure the cauldron dnf repo definitions exist before enabling media.\n"
        "    safe_install mageia-repos-cauldron\n"
        '    log INFO "Enabling Mageia cauldron nonfree + tainted repos..."',
        why="bootstrap log",
    )
    sub(
        '        log SUCCESS "OpenMandriva extra (community) + restricted (codecs) + non-free (proprietary) repos enabled"',
        '        log SUCCESS "Mageia cauldron nonfree (proprietary) + tainted (codecs) repos enabled"',
        why="bootstrap success",
    )
    # Installing mageia-repos-cauldron only drops in the cauldron repo
    # DEFINITIONS; their metadata is not downloaded until a refresh. Without it,
    # package_exists() (dnf info / repoquery) queries empty cauldron caches and
    # reports almost every not-yet-installed package as "not in repos" (htop,
    # tmux, zsh, fzf, ... all read as missing). Force a refresh after the switch.
    sub(
        "    om_repo_enabled non-free  || { enable_om_repo non-free  || ok=false; }\n"
        "    if $ok; then",
        "    om_repo_enabled non-free  || { enable_om_repo non-free  || ok=false; }\n"
        "    # The cauldron repo set was just (re)defined; pull its metadata so the\n"
        "    # package_exists() checks below see the catalog instead of an empty cache.\n"
        '    log INFO "Refreshing dnf metadata for the cauldron repos..."\n'
        "    dnf --refresh makecache 2>/dev/null || dnf makecache 2>/dev/null || true\n"
        "    if $ok; then",
        why="post-bootstrap metadata refresh",
    )

    # ---- 8. NVIDIA: OM prebuilt kmods -> Mageia DKMS -----------------------
    sub(
        '''# ========== NVIDIA DRIVER (OpenMandriva non-free repo) ==========
# OpenMandriva pre-builds the NVIDIA kernel modules in its own ABF build farm
# per kernel release - `dnf install nvidia nvidia-kmod-open-desktop --refresh`
# from the non-free repo is the official wiki install command (the -open
# variant matches the Fedora script's open-kernel-module choice; prebuilt
# means NO akmod compile loop to poll, unlike the Fedora RPM Fusion path).
# The kmod package matches the default kernel-desktop flavor; a non-default
# kernel flavor needs the matching nvidia-kmod-open-<flavor> package instead.
# Opt-in only, same reasoning as the Fedora script: real hardware-specific
# state, not a package to fire blindly.''',
        '''# ========== NVIDIA DRIVER (Mageia nonfree repo) ==========
# Mageia ships the proprietary NVIDIA driver in its nonfree repo and builds the
# kernel module locally via DKMS: dkms-nvidia-current for the current series,
# dkms-nvidia390 / dkms-nvidia340 for legacy GPUs. This differs from
# OpenMandriva's prebuilt kmods and Fedora's RPM Fusion akmods - DKMS compiles
# once at install and rebuilds on kernel updates. The exact package depends on
# the GPU generation and release, so this is best-effort; `dnf search
# dkms-nvidia` shows what's available. Opt-in only: real hardware-specific
# state, not a package to fire blindly.''',
        why="nvidia header",
    )
    sub(
        '    local msg="Install the NVIDIA driver (nvidia + nvidia-kmod-open-desktop)?\\n\\nOpen kernel modules, prebuilt by OpenMandriva for the default kernel-desktop flavor - no local compile step. Only do this on a machine with an NVIDIA GPU. A reboot is needed after install to load the module."',
        '    local msg="Install the NVIDIA proprietary driver (dkms-nvidia-current + nvidia-current)?\\n\\nMageia\'s current-series NVIDIA driver from nonfree; the kernel module is built locally via DKMS. Only do this on a machine with a reasonably recent NVIDIA GPU (older cards need dkms-nvidia390/340 instead). A reboot is needed after install."',
        why="nvidia msg",
    )
    sub(
        '    log INFO "Installing NVIDIA driver (prebuilt kmods from non-free)..."',
        '    log INFO "Installing NVIDIA driver (DKMS build from nonfree)..."',
        why="nvidia log",
    )
    sub(
        "    dnf install -y --refresh nvidia nvidia-kmod-open-desktop 2>/dev/null",
        "    dnf install -y --refresh dkms-nvidia-current nvidia-current x11-driver-video-nvidia-current 2>/dev/null",
        why="nvidia install",
    )
    sub(
        "    if is_installed nvidia-kmod-open-desktop || is_installed nvidia; then",
        "    if is_installed dkms-nvidia-current || is_installed nvidia-current; then",
        why="nvidia verify",
    )
    sub(
        '        INSTALLED_PACKAGES+=("nvidia + nvidia-kmod-open-desktop"); ((TOTAL_INSTALLED++))\n'
        '        log SUCCESS "Installed: NVIDIA driver (nvidia + nvidia-kmod-open-desktop)"',
        '        INSTALLED_PACKAGES+=("nvidia (dkms-nvidia-current)"); ((TOTAL_INSTALLED++))\n'
        '        log SUCCESS "Installed: NVIDIA driver (dkms-nvidia-current + nvidia-current)"',
        why="nvidia installed msg",
    )
    sub(
        '        log INFO "A non-default kernel flavor needs the matching nvidia-kmod-open-<flavor> package"',
        '        log INFO "DKMS rebuilds the module on kernel updates; a too-old GPU for -current wants dkms-nvidia390/340"',
        why="nvidia flavor note",
    )
    sub(
        '        FAILED_PACKAGES+=("nvidia + nvidia-kmod-open-desktop"); ((TOTAL_FAILED++))\n'
        '        log WARNING "NVIDIA driver install failed - try: sudo dnf install nvidia nvidia-kmod-open-desktop"',
        '        FAILED_PACKAGES+=("nvidia (dkms-nvidia-current)"); ((TOTAL_FAILED++))\n'
        '        log WARNING "NVIDIA driver install failed - run \'dnf search dkms-nvidia\' and pick the series for your GPU"',
        why="nvidia fail msg",
    )

    # ---- 9. Leftover OM references the capital-O global rename misses -------
    # Run-as instructions -> the Mageia filename (line 3 keeps the provenance
    # reference to post-install-openmandriva.sh deliberately).
    sub(
        "# Run as: chmod +x post-install-openmandriva.sh && sudo ./post-install-openmandriva.sh",
        "# Run as: chmod +x post-install-mageia.sh && sudo ./post-install-mageia.sh",
        why="run-as line",
    )
    # TUI header + NVIDIA menu item (user-facing).
    sub(
        '"OPENMANDRIVA ${OM_VERSION:-Lx}  ·  POST-INSTALL" "dnf5 · restricted + non-free repos · Flathub"',
        '"MAGEIA ${OM_VERSION:-cauldron}  ·  POST-INSTALL" "dnf5 · nonfree + tainted repos · Flathub"',
        why="tui header",
    )
    sub(
        'ui_item 1 "NVIDIA Driver (nvidia + nvidia-kmod-open-desktop, non-free repo)"',
        'ui_item 1 "NVIDIA Driver (dkms-nvidia-current, nonfree repo)"',
        why="nvidia menu item",
    )
    # Functional paths (log file, theme state marker) + lingering prose.
    out = out.replace("/var/log/openmandriva_post_install_", "/var/log/mageia_post_install_")
    out = out.replace("/var/lib/openmandriva-postinstall-themes/", "/var/lib/mageia-postinstall-themes/")
    out = out.replace("openmandriva-repos", "mageia-repos")
    out = out.replace("dnf install nvidia nvidia-kmod-open-desktop --refresh",
                      "dnf install dkms-nvidia-current nvidia-current --refresh")
    out = out.replace("OPENMANDRIVA", "MAGEIA")

    # ---- 9b. Mageia package-name fixes (OM names that don't exist here) -----
    # zenity: OpenMandriva splits the GTK build into zenity-gtk (+ zenity-wrapper);
    # Mageia ships a single "zenity" package that provides /usr/bin/zenity directly.
    sub(
        '    # OpenMandriva names: the real GTK zenity is zenity-gtk (it pulls in\n'
        '    # zenity-wrapper, which provides /usr/bin/zenity; a plain "zenity" only\n'
        '    # resolves to qarma, a Qt clone, on Rock), and secret-tool is in\n'
        '    # libsecret-tools ("libsecret" only resolves to the bare library,\n'
        '    # lib64secret1_0, without secret-tool).\n'
        '    batch_install "AI Key Manager deps" zenity-gtk libsecret-tools gnome-keyring curl',
        '    # Mageia ships a single GTK zenity package (just "zenity") that provides\n'
        '    # /usr/bin/zenity directly - no zenity-gtk/zenity-wrapper split like\n'
        '    # OpenMandriva\'s. secret-tool is in libsecret-tools (the bare "libsecret"\n'
        '    # only resolves to the library, lib64secret1_0, without secret-tool).\n'
        '    batch_install "AI Key Manager deps" zenity libsecret-tools gnome-keyring curl',
        why="zenity-gtk comment+deps",
    )
    out = out.replace("zenity-gtk", "zenity")  # Wine deps line (and any stragglers)
    # nload is not packaged for Mageia in any release (confirmed via repology),
    # so drop it from the System Utils batch - otherwise it's a guaranteed
    # FAILED entry. nethogs/iftop/vnstat/glances cover the same ground.
    sub(
        "    # OpenMandriva's vnstat package is uninstallable (it requires\n"
        "    # user(vnstat)/group(vnstat), which nothing provides).\n"
        "    batch_install \"System Utils\" \\\n"
        "        htop iotop sysstat \\\n"
        "        nethogs iftop nload tcpdump wireshark \\\n",
        "    # OpenMandriva's vnstat package is uninstallable (it requires\n"
        "    # user(vnstat)/group(vnstat), which nothing provides). nload is not\n"
        "    # packaged for Mageia at all (no build in any release), so it's dropped\n"
        "    # here; nethogs/iftop/vnstat/glances cover the same ground.\n"
        "    batch_install \"System Utils\" \\\n"
        "        htop iotop sysstat \\\n"
        "        nethogs iftop tcpdump wireshark \\\n",
        why="drop unpackaged nload",
    )
    # papirus-icon-theme: packaged on OpenMandriva but NOT on Mageia. adwaita and
    # Breeze (breeze-icons) are packaged; Papirus is a plain icon folder, so drop
    # it from the dnf batch and pull the prebuilt theme from upstream like the
    # Numix/Obsidian sets right below it.
    sub(
        "    # Packaged on OpenMandriva: papirus-icon-theme, adwaita-icon-theme and\n"
        "    # Breeze (named breeze-icons here, not breeze-icon-theme). Numix,\n"
        "    # Numix Circle and Obsidian aren't packaged on Rock or Rolling - they're\n"
        "    # plain icon folders, so install them from their upstream repos below.\n"
        "    # (This line used to end in a doubled backslash, which ended the command\n"
        "    # there - batch_install got no packages and every name below it ran as\n"
        "    # a command of its own, \"command not found\".)\n"
        "    batch_install \"Icon Sets\" \\\n"
        "        papirus-icon-theme \\\n"
        "        breeze-icons \\\n"
        "        adwaita-icon-theme\n",
        "    # Packaged on Mageia: adwaita-icon-theme and Breeze (breeze-icons). Papirus\n"
        "    # is NOT packaged on Mageia (only OpenMandriva ships it), and neither are\n"
        "    # Numix/Numix Circle/Obsidian - they're plain icon folders installed from\n"
        "    # their upstream repos below.\n"
        "    batch_install \"Icon Sets\" \\\n"
        "        breeze-icons \\\n"
        "        adwaita-icon-theme\n"
        "    # Papirus: unpackaged on Mageia, so pull the prebuilt theme folders from\n"
        "    # the upstream repo (large; shallow clone) like the sets below.\n"
        "    install_git_icon_theme \"Papirus icons\" https://github.com/PapirusDevelopmentTeam/papirus-icon-theme.git 'Papirus*'\n",
        why="papirus unpackaged -> upstream",
    )
    # Gemini CLI needs npm; on Mageia the npm package does not pull nodejs on its
    # own, so install both (harmless where npm already depends on nodejs).
    out = out.replace("pm_install npm >/dev/null 2>&1",
                      "pm_install nodejs npm >/dev/null 2>&1")

    # ---- 10. Global prose rename + edition labels --------------------------
    out = out.replace("OpenMandriva", "Mageia")
    out = out.replace("ROME rolling", "cauldron")

    DST.write_text(out, encoding="utf-8")
    DST.chmod(0o755)
    print(f"wrote {DST} ({out.count(chr(10)) + 1} lines)")
    for w in warnings:
        print("WARN:", w)


if __name__ == "__main__":
    main()
