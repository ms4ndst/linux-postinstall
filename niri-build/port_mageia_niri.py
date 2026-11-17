#!/usr/bin/env python3
"""Port openmandriva-niri-setup.sh -> mageia-niri-setup.sh.

Mageia and OpenMandriva are both Mandriva descendants (dnf available, lib64*
library naming, largely shared package names), so the OpenMandriva niri setup -
which already did all the Mandriva-ification (lib64 renames, strict=0 installs,
the rofi/dunst/gammastep/xwayland-satellite source builds) - is a far closer
base than Fedora. This port therefore transforms the OM OUTPUT, changing only
what differs between the two Mandriva distros:

  - Repo setup: OpenMandriva's repo-tree (cooker/rolling/rock) detection and
    extra/restricted/non-free enabling -> Mageia cauldron's dnf repos
    (mageia-repos-cauldron, cauldron-<arch>-{nonfree,tainted}). Target is
    cauldron because the Wayland stack + niri build deps are current there.
  - niri itself: PACKAGED on OpenMandriva, but NOT on Mageia and there is no
    COPR, so it is BUILT FROM SOURCE (cargo) before the mandatory-niri gate.
    Build deps are declared as pkgconfig() capabilities so dnf resolves them to
    whatever Mageia package provides them (dodging lib64*-devel name guessing);
    the list mirrors niri's upstream Getting-Started build deps. xwayland-
    satellite is already built from source by the OM port (niri has no built-in
    XWayland) and carries over unchanged.
  - Package names + the strict=0 install list carry over verbatim from the OM
    port; strict=0 skips any name Mageia happens not to carry, and the existing
    source/pip/binary fallbacks cover the rest. Any real Mageia-vs-OM delta that
    surfaces on a test run is a one-line add here.
  - Prose: "OpenMandriva" -> "Mageia" globally (after the structural swaps), so
    the source-build fallback messages read correctly; the header paragraph and
    the mandatory-niri message are rewritten for Mageia specifically.

Chained port: run the Fedora build, then the OM niri port, then this. Every step
is anchored on unique strings - never line numbers; a stale anchor warns.

Usage: python3 -I port_mageia_niri.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
SRC = ROOT / "openmandriva-niri-setup.sh"
DST = ROOT / "mageia-niri-setup.sh"

# Reuse the OM preamble string as the exact anchor to replace (it is what the OM
# port injected, so it matches the output byte-for-byte).
sys.path.insert(0, str(ROOT / "sway-build"))
import port_openmandriva as sp  # noqa: E402

OM_PREAMBLE = sp.OM_PREAMBLE

MAGEIA_PREAMBLE = r'''
# --- Mageia repository setup (cauldron; dnf) ------------------------------
# Mageia does not package niri and has no COPR, so this rice targets cauldron
# (the rolling branch), where the Wayland stack and niri's build deps are
# current - niri + xwayland-satellite are built from source further down. The
# free "core" media (cauldron-<arch>) is enabled by default; enable nonfree +
# tainted for firmware/codecs and the few restricted apps this install pulls in.
MGA_ARCH="$(uname -m)"
# Make sure the cauldron dnf repo definitions exist (no-op if already present).
sudo dnf install -y mageia-repos-cauldron >/dev/null 2>&1 || true
mga_enable_repo() {
  local repoid="$1"
  # dnf5 (Mageia 10) and dnf4 spellings, then a direct .repo edit as last resort.
  sudo dnf config-manager setopt "$repoid.enabled=1" >/dev/null 2>&1 && return 0
  sudo dnf config-manager --set-enabled "$repoid" >/dev/null 2>&1 && return 0
  local f
  for f in /etc/yum.repos.d/*.repo; do
    [ -f "$f" ] || continue
    if grep -q "^\[$repoid\]" "$f" 2>/dev/null; then
      local tmp
      tmp=$(mktemp)
      if awk -v id="[$repoid]" '
        /^\[/ { inrepo = ($0 == id); print; next }
        inrepo && /^enabled[[:space:]]*=/ { print "enabled=1"; next }
        { print }
      ' "$f" > "$tmp" && sudo cp "$tmp" "$f"; then
        rm -f "$tmp"; return 0
      fi
      rm -f "$tmp"
    fi
  done
  warn "Could not enable '$repoid' - check /etc/yum.repos.d/*.repo"
  return 1
}
log "Enabling Mageia cauldron nonfree + tainted repositories (arch: $MGA_ARCH)..."
mga_enable_repo "cauldron-$MGA_ARCH-nonfree"
mga_enable_repo "cauldron-$MGA_ARCH-tainted"
sudo dnf --refresh makecache 2>/dev/null || true

'''

# Self-contained niri source build. It runs BEFORE the mandatory-niri gate and
# does NOT use om_build_deps/om_fetch_tarball (those helpers are defined later in
# the file, in the section-1a source builds), so it inlines the dnf install and
# the fetch. Deps are pkgconfig() capabilities (dnf resolves them regardless of
# the exact lib64*-devel name); the set mirrors niri's upstream build deps.
# Pinned to v26.04 (the version on the author's Fedora box). niri needs its
# session resources installed too (the .desktop, niri-session wrapper and the
# systemd user units), or GDM won't offer the session and `niri --session`
# won't integrate with systemd - so install those from the source tree.
NIRI_BUILD = r'''# niri is NOT packaged on Mageia and there is no COPR, so build it from source
# (a large Rust build). This is the rice's compositor, so it runs BEFORE the
# mandatory-niri gate below. Build deps via pkgconfig() capabilities so dnf maps
# them to whatever Mageia package provides them; the list mirrors niri's own
# Getting-Started deps (github.com/YaLTeR/niri/wiki/Getting-Started).
if ! command -v niri >/dev/null 2>&1; then
  log "Building niri from source (not packaged on Mageia; this is a large Rust build and may take several minutes)..."
  sudo dnf install -y --setopt=strict=0 \
    cargo rust clang gcc pkgconf \
    'pkgconfig(wayland-client)' 'pkgconfig(wayland-protocols)' 'pkgconfig(libinput)' \
    'pkgconfig(xkbcommon)' 'pkgconfig(gbm)' 'pkgconfig(libudev)' 'pkgconfig(dbus-1)' \
    'pkgconfig(libsystemd)' 'pkgconfig(libseat)' 'pkgconfig(libpipewire-0.3)' \
    'pkgconfig(pango)' 'pkgconfig(cairo-gobject)' 'pkgconfig(libdisplay-info)' \
    >/dev/null 2>&1 || true
  MGT="$(mktemp -d)"
  if curl -fsSL --retry 3 -o "$MGT/niri.tar.gz" \
        https://github.com/YaLTeR/niri/archive/refs/tags/v26.04.tar.gz 2>/dev/null \
      && tar -xzf "$MGT/niri.tar.gz" -C "$MGT" \
      && nd="$(find "$MGT" -mindepth 1 -maxdepth 1 -type d | head -1)" \
      && [ -n "$nd" ] \
      && ( cd "$nd" && cargo build --release ) \
      && sudo install -Dm755 "$nd/target/release/niri" /usr/bin/niri \
      && sudo install -Dm755 "$nd/resources/niri-session" /usr/bin/niri-session \
      && sudo install -Dm644 "$nd/resources/niri.desktop" /usr/share/wayland-sessions/niri.desktop \
      && sudo install -Dm644 "$nd/resources/niri-portals.conf" /usr/share/xdg-desktop-portal/niri-portals.conf \
      && sudo install -Dm644 "$nd/resources/niri.service" /usr/lib/systemd/user/niri.service \
      && sudo install -Dm644 "$nd/resources/niri-shutdown.target" /usr/lib/systemd/user/niri-shutdown.target \
      && command -v niri >/dev/null 2>&1; then
    log "niri $(niri --version 2>/dev/null | head -1) built and installed to /usr/bin (session files in place)."
  else
    warn "niri build failed - the rice cannot run without it. Check the cargo/rust build output and the pkgconfig() dev libraries above, then re-run."
  fi
  rm -rf "$MGT"
fi

'''

MAGEIA_MANDATORY = '''if ! command -v niri >/dev/null 2>&1; then
  warn "niri is not installed and the source build above did not produce it."
  warn "Mageia does not package niri; fix the build deps (cargo/rust + the"
  warn "pkgconfig() dev libraries listed above) and re-run, or build it by hand:"
  warn "  git clone https://github.com/YaLTeR/niri && cd niri && cargo build --release"
  exit 1
fi'''

HEADER_OLD = '''# Ported from this repo's fedora-niri-setup.sh. Almost all of this file - the
# niri config, every heredoc config, the HANCORE theme pipeline, all helper
# scripts - is distro-independent and carried over byte-for-byte. Only the
# package-manager surface changes: OpenMandriva repo-tree detection +
# extra/restricted/non-free enabling, --setopt=strict=0 installs, verified
# package renames, and source/pip/binary installs for what OpenMandriva doesn't
# package (Wayland rofi, current dunst, gammastep on Rock, udiskie, nwg-displays,
# satty). niri itself is PACKAGED on OpenMandriva Rolling (ROME) and Cooker - no
# COPR is needed (unlike Fedora); an older edition without the niri package is
# caught by the mandatory check below.'''

HEADER_NEW = '''# Ported from this repo's openmandriva-niri-setup.sh (Mageia and OpenMandriva
# share the Mandriva lineage - dnf, lib64* naming, mostly shared package names).
# Almost all of this file - the niri config, every heredoc config, the HANCORE
# theme pipeline, all helper scripts - is distro-independent and carried over
# byte-for-byte. What changes for Mageia: cauldron dnf repo setup (nonfree +
# tainted), --setopt=strict=0 installs (names Mageia doesn't carry are skipped),
# and the source/pip/binary builds inherited from the OM port. Crucially, Mageia
# does NOT package niri and has no COPR, so niri itself is BUILT FROM SOURCE
# (cargo) before the mandatory-niri gate; xwayland-satellite is likewise built
# from source (niri has no built-in XWayland). Targets cauldron, where the
# Wayland stack and niri's build deps are current.
#
# NOTE: best-effort and UNTESTED on a real Mageia box at authoring time - the
# niri build pins v26.04 and relies on pkgconfig() deps; package-name or
# repo-id deltas may need a one-line fix after the first run.'''


def main():
    if not SRC.is_file():
        sys.exit(f"ERROR: {SRC} not found - run the Fedora build and the OM niri port first.")
    out = SRC.read_text(encoding="utf-8")
    warnings = []

    def sub(old, new, why=""):
        nonlocal out
        if old not in out:
            warnings.append(f"stale anchor ({why or old[:50]!r})")
            return
        out = out.replace(old, new, 1)

    # 1. Header: title line is fixed by the global rename below; rewrite the
    #    OM-specific description paragraph for Mageia.
    sub(HEADER_OLD, HEADER_NEW, why="header paragraph")

    # 2. Repo preamble: OpenMandriva repo-tree enabling -> Mageia cauldron repos.
    sub(OM_PREAMBLE, MAGEIA_PREAMBLE, why="OM_PREAMBLE block")

    # 3. niri from source, injected right before the mandatory-niri gate, and
    #    the gate message rewritten for Mageia.
    gate_old = '''# niri itself is mandatory - bail early with a clear message if the dnf install
# did not land it, rather than writing configs for a compositor that is absent.
if ! command -v niri >/dev/null 2>&1; then
  warn "niri is not installed. OpenMandriva packages niri in its Rolling (ROME)"
  warn "and Cooker repositories - switch to one of those editions, then re-run:"
  warn "  sudo dnf install niri"
  exit 1
fi'''
    gate_new = (
        NIRI_BUILD
        + "# niri itself is mandatory - after the source build above it must exist, or\n"
        + "# the rice has nothing to configure.\n"
        + MAGEIA_MANDATORY
    )
    sub(gate_old, gate_new, why="mandatory-niri gate")

    # 4. The main dnf-install's leading log line still says niri comes from dnf;
    #    niri is built from source on Mageia, so adjust the wording.
    sub(
        "log \"Installing niri + the Wayland rice toolkit via dnf (--setopt=strict=0: names OpenMandriva doesn't carry are skipped, then built or substituted below)...\"",
        "log \"Installing the Wayland rice toolkit via dnf (--setopt=strict=0: names Mageia doesn't carry are skipped, then built or substituted below; niri itself is built from source above the gate)...\"",
        why="install log line",
    )

    # 4b. papirus-icon-theme is not packaged on Mageia (only OpenMandriva has
    #     it). strict=0 would skip it, but it still prints a "no match" line and
    #     drops Papirus entirely; post-install-mageia.sh installs Papirus from
    #     upstream, so just drop it from this lean bootstrap's dnf list.
    sub(
        "  lxappearance papirus-icon-theme adwaita-cursor-theme \\\n",
        "  lxappearance adwaita-cursor-theme \\\n",
        why="drop unpackaged papirus-icon-theme",
    )

    # 5. Global prose rename (after the structural swaps, which matched on the
    #    original OpenMandriva strings). Fixes the source-build fallback
    #    messages ("not packaged for OpenMandriva" -> "... Mageia"), the dnf
    #    abort message, and the fastfetch --logo OpenMandriva -> Mageia (a real
    #    fastfetch logo name).
    out = out.replace("OpenMandriva", "Mageia")

    DST.write_text(out, encoding="utf-8")
    print(f"wrote {DST} ({out.count(chr(10)) + 1} lines)")
    for w in warnings:
        print("WARN:", w)


if __name__ == "__main__":
    main()
