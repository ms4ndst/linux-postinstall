#!/usr/bin/env python3
"""polybar .ini  ->  waybar config.jsonc + style.css  (faithful 1:1 compiler)

The insight: every polybar theme in this rice is expressed in the SAME
primitives (a [colors] block, [bar/*] with ordered modules-*, and [module/*]
of type internal/* | custom/script | custom/text). The visual language
(powerline pills / flat / chips / capsules) EMERGES from those primitives, so a
single compiler that renders each module's glyph + fg/bg + clicks faithfully
reproduces every theme's look without per-theme special-casing.

This is a prototype/first pass. It emits:
  <name>/config.jsonc   - one bar object (top-primary module set)
  <name>/style.css      - per-module colors/fonts/borders

Run:  python3 -I polybar2waybar.py <src.ini> <outdir>
"""
import json, re, sys, pathlib

# ---------------------------------------------------------------- INI parsing
def parse_ini(text):
    """Order-preserving polybar INI parser. Sections -> dict of key->value.
    Only lines whose first non-space char is ; or # are comments (so inline ;
    inside font specs / quoted labels is preserved)."""
    sections = {}           # name -> dict
    order = []              # section names in order
    cur = None
    for raw in text.splitlines():
        line = raw.rstrip("\n")
        s = line.strip()
        if not s or s[0] in ";#":
            continue
        m = re.match(r"^\[([^\]]+)\]$", s)
        if m:
            cur = m.group(1)
            sections.setdefault(cur, {})
            order.append(cur)
            continue
        if cur is None:
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        # strip one layer of surrounding quotes, preserving inner spaces/glyphs
        if len(val) >= 2 and val[0] == '"' and val[-1] == '"':
            val = val[1:-1]
        sections[cur][key] = val
    return sections, order

# ---------------------------------------------------------------- resolving
def build_resolver(sections):
    colors = sections.get("colors", {})
    def resolve(val, self_sec=None):
        if val is None:
            return None
        prev = None
        # iterate until no more ${...} (handles ${self.x} -> ${colors.y})
        while prev != val:
            prev = val
            def repl(m):
                ref = m.group(1)
                if ref.startswith("colors."):
                    return colors.get(ref[len("colors."):], m.group(0))
                if ref.startswith("self.") and self_sec is not None:
                    return self_sec.get(ref[len("self."):], m.group(0))
                if ref.startswith("env:"):
                    # ${env:VAR:default}
                    body = ref[len("env:"):]
                    default = body.split(":", 1)[1] if ":" in body else ""
                    return default
                return m.group(0)
            val = re.sub(r"\$\{([^}]+)\}", repl, val)
        return val
    return resolve

def is_hex(c):
    return bool(c) and re.match(r"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$", c)

def css_color(c):
    """polybar hex is #RRGGBB or #AARRGGBB; CSS wants #RRGGBB or rgba()."""
    if not c:
        return None
    if re.match(r"^#[0-9a-fA-F]{8}$", c):
        a = int(c[1:3], 16) / 255.0
        r, g, b = int(c[3:5], 16), int(c[5:7], 16), int(c[7:9], 16)
        return f"rgba({r},{g},{b},{a:.3f})"
    return c

# ---------------------------------------------------------------- module maps
# polybar internal type -> (waybar module id, handler)
def font_px(fontspec):
    m = re.search(r"size=(\d+)", fontspec or "")
    return int(m.group(1)) if m else None

def main():
    src = pathlib.Path(sys.argv[1])
    outdir = pathlib.Path(sys.argv[2]) / src.stem
    outdir.mkdir(parents=True, exist_ok=True)
    raw_text = src.read_text(encoding="utf-8")
    sections, order = parse_ini(raw_text)
    R = build_resolver(sections)

    # --- bar geometry: prefer top-primary, resolving inherit chain
    def bar(name):
        b = dict(sections.get(name, {}))
        inh = b.get("inherit")
        if inh and inh in sections:
            base = dict(sections[inh])
            base.update(b)
            b = base
        return b
    # Which bar is the "primary" one? Themes name it in a dropped comment
    # `; launch-primary = <bar>` (gh0stzk uses named bars like gz-aline-bar);
    # otherwise top-primary, otherwise the first [bar/*] that defines modules.
    def pick_primary_bars():
        """Return the list of bar section names that form the primary bar.
        Themes may name several in `; launch-primary = a b c` (gh0stzk rices
        that ship as multiple stacked bars) - merge them into one waybar."""
        m = re.search(r"^;\s*launch-primary\s*=\s*(.+)$", raw_text, re.M)
        if m:
            names = [f"bar/{n}" for n in m.group(1).split() if f"bar/{n}" in sections]
            if names:
                return names
        if "bar/top-primary" in sections:
            return ["bar/top-primary"]
        for name in order:
            if name.startswith("bar/"):
                b = bar(name)
                if (b.get("modules-left") or b.get("modules-center")
                        or b.get("modules-right")):
                    return [name]
        return ["bar/base"]
    primary_bars = [bar(n) for n in pick_primary_bars()]
    primary = primary_bars[0]
    height = int(re.sub(r"\D", "", primary.get("height", "30")) or 30)
    radius = primary.get("radius", "0")
    radius = re.sub(r"[^0-9.]", "", radius.split(":")[0]) or "0"
    bar_bg = css_color(R(primary.get("background")))
    bar_fg = css_color(R(primary.get("foreground")))
    fonts = [primary.get(f"font-{i}") for i in range(10) if primary.get(f"font-{i}")]
    base_font_family = (fonts[0].split(":")[0] if fonts else "JetBrainsMono Nerd Font")
    base_font_size = font_px(fonts[0]) if fonts else 10
    # font slot (label-font = N) -> px size, using the 1-indexed polybar slots
    slot_px = {}
    for i, f in enumerate(fonts):
        slot_px[i + 1] = font_px(f)  # polybar label-font is 1-indexed

    def mod_sections(bars):
        left, center, right = [], [], []
        for barcfg in bars:
            left += (barcfg.get("modules-left") or "").split()
            center += (barcfg.get("modules-center") or "").split()
            right += (barcfg.get("modules-right") or "").split()
        return left, center, right
    left, center, right = mod_sections(primary_bars)

    waybar = {
        "layer": "top", "position": "top", "height": height,
        "modules-left": [], "modules-center": [], "modules-right": [],
    }
    css = []
    css.append("* { border: none; border-radius: 0; min-height: 0;"
               f" font-family: \"{base_font_family}\", \"JetBrains Mono\";"
               f" font-size: {base_font_size}pt; }}")
    win = [f"background: {bar_bg or 'rgba(30,30,46,1)'};",
           f"color: {bar_fg or '#cdd6f4'};"]
    css.append("window#waybar { " + " ".join(win) + " }")
    if radius and float(radius) > 0:
        css.append(f"window#waybar {{ border-radius: {radius}px; }}")

    used_ids = []

    def waybar_id(poly_name, sec):
        t = sec.get("type", "")
        internal = {
            "internal/date": "clock",
            "internal/pulseaudio": "pulseaudio",
            "internal/memory": "memory",
            "internal/cpu": "cpu",
            "internal/battery": "battery",
            "internal/backlight": "backlight",
            "internal/tray": "tray",
            "internal/xkeyboard": "sway/language",
        }
        if t == "internal/i3":
            return "sway/workspaces"
        if t == "internal/network":
            return "network"
        if t in internal:
            return internal[t]
        # custom/script, custom/text, custom/ipc, bspwm remnants -> custom/<name>
        return f"custom/{poly_name}"

    def css_sel(wid):
        # CSS selector for a waybar module id
        if wid.startswith("custom/"):
            return "#custom-" + wid.split("/", 1)[1]
        if wid == "sway/workspaces":
            return "#workspaces"
        if wid == "sway/language":
            return "#language"
        return "#" + wid.split("/")[-1]

    def emit_css_box(wid, fg=None, bg=None, ul=None, ol=None, pad=None, font_slot=None):
        decls = []
        if fg: decls.append(f"color: {css_color(fg)};")
        if bg: decls.append(f"background: {css_color(bg)};")
        if ul: decls.append(f"border-bottom: 2px solid {css_color(ul)};")
        if ol: decls.append(f"border-top: 2px solid {css_color(ol)};")
        if pad is not None:
            try:
                p = int(pad); decls.append(f"padding: 0 {p}px;")
            except ValueError:
                pass
        if font_slot and slot_px.get(int(font_slot) if str(font_slot).isdigit() else 0):
            decls.append(f"font-size: {slot_px[int(font_slot)]}pt;")
        if decls:
            css.append(f"{css_sel(wid)} {{ " + " ".join(decls) + " }")

    # clicks: polybar click-left/middle/right/scroll-up/down -> waybar on-*
    def clicks(sec, mod):
        cmap = {"click-left": "on-click", "click-middle": "on-click-middle",
                "click-right": "on-click-right", "scroll-up": "on-scroll-up",
                "scroll-down": "on-scroll-down"}
        for pk, wk in cmap.items():
            if sec.get(pk):
                mod[wk] = re.sub(r"\s*&\s*$", "", R(sec[pk])).strip()

    def strip_action(s):
        # remove polybar %{A1:cmd:}...%{A} click-zone markup, keep inner text
        if s is None:
            return s
        s = re.sub(r"%\{A\d?:[^}]*:\}", "", s)
        s = s.replace("%{A}", "")
        return s

    def handle(poly_name):
        sec = sections.get(f"module/{poly_name}")
        if sec is None:
            return None
        wid = waybar_id(poly_name, sec)
        t = sec.get("type", "")
        mod = {}
        if t == "internal/i3":
            # ws-icon-N = <match>;<glyph>  -> waybar format-icons {<match>:<glyph>}.
            # ws-icon-default = <glyph> (no ';'). Strip polybar %{...} markup
            # from the glyph (waybar colors via CSS, not inline tags).
            icons = {}
            for k, v in sec.items():
                m = re.match(r"ws-icon-(\d+|default)$", k)
                if not m:
                    continue
                if m.group(1) == "default":
                    glyph = re.sub(r"%\{[^}]*\}", "", v).strip()
                    if glyph:
                        icons["default"] = glyph
                else:
                    name, _, glyph = v.partition(";")
                    glyph = re.sub(r"%\{[^}]*\}", "", glyph).strip()
                    if glyph:
                        icons[name.strip()] = glyph
            mod = {"disable-scroll": True, "all-outputs": False,
                   "format": "{icon}" if icons else "{name}"}
            if icons:
                mod["format-icons"] = icons
            # focused/unfocused/urgent colors -> CSS
            for state, cls in (("focused", "button.focused"),
                               ("unfocused", "button"),
                               ("urgent", "button.urgent")):
                fg = R(sec.get(f"label-{state}-foreground"))
                bg = R(sec.get(f"label-{state}-background"))
                ul = R(sec.get(f"label-{state}-underline"))
                decls = []
                if fg: decls.append(f"color: {css_color(fg)};")
                if bg: decls.append(f"background: {css_color(bg)};")
                if ul: decls.append(f"border-bottom: 2px solid {css_color(ul)};")
                if decls:
                    css.append(f"#workspaces {cls} {{ " + " ".join(decls) + " }")
        elif t == "internal/date":
            datef = sec.get("date", "%Y-%m-%d")
            timef = sec.get("time", "%H:%M")
            # waybar's clock renders strftime only INSIDE a `{:...}` placeholder;
            # a bare %Y-%m-%d prints literally. Wrap the date..time span in one
            # `{:...}` (date precedes time in every theme here), keeping any
            # surrounding icon/padding text outside the braces.
            label = strip_action(sec.get("label", ""))
            has_d, has_t = "%date%" in label, "%time%" in label
            if has_d and has_t:
                lbl = label.replace("%date%", "{:" + datef, 1).replace("%time%", timef + "}", 1).strip()
            elif has_d:
                lbl = label.replace("%date%", "{:" + datef + "}").strip()
            elif has_t:
                lbl = label.replace("%time%", "{:" + timef + "}").strip()
            else:
                lbl = "{:" + datef + "  " + timef + "}"
            mod = {"format": lbl, "interval": 1, "tooltip": False}
            clicks(sec, mod)
            # calendar launch was in the %{A:...:} zone
            m = re.search(r"%\{A\d?:([^:]*(?::[^:]*)*?):\}", sec.get("label", ""))
            if m and "on-click" not in mod:
                mod["on-click"] = re.sub(r"\s*&\s*$", "", m.group(1)).strip()
            emit_css_box(wid, fg=R(sec.get("label-foreground")),
                         bg=R(sec.get("format-background")),
                         font_slot=sec.get("label-font"))
        elif t == "internal/pulseaudio":
            mod = {"format": strip_action(sec.get("label-volume", "{volume}%")).replace("%percentage%", "{volume}"),
                   "format-muted": strip_action(sec.get("label-muted", "muted")).replace("%percentage%", "{volume}"),
                   "tooltip": False}
            clicks(sec, mod)
            emit_css_box(wid, fg=R(sec.get("label-volume-foreground")),
                         bg=R(sec.get("format-volume-background")))
        elif t == "internal/network":
            lbl = strip_action(sec.get("label-connected", "{ifname}")).replace("%ifname%", "{ifname}")
            mod = {"format-ethernet": lbl.strip(), "format-disconnected": "",
                   "interface": sec.get("interface", "") or None, "tooltip": False}
            mod = {k: v for k, v in mod.items() if v is not None}
            clicks(sec, mod)
            emit_css_box(wid, fg=R(sec.get("label-connected-foreground")),
                         bg=R(sec.get("format-connected-background")))
        elif t == "internal/battery":
            mod = {"format": strip_action(sec.get("label-discharging", "{capacity}%")).replace("%percentage%", "{capacity}"),
                   "format-charging": strip_action(sec.get("label-charging", "{capacity}%")).replace("%percentage%", "{capacity}"),
                   "format-full": strip_action(sec.get("label-full", "Full")),
                   "tooltip": False}
            emit_css_box(wid, fg=R(sec.get("label-discharging-foreground")),
                         bg=R(sec.get("format-discharging-background")))
        elif t in ("internal/memory",):
            mod = {"format": strip_action(sec.get("label", "{percentage}%")).replace("%percentage_used%", "{percentage}"),
                   "interval": 2, "tooltip": False}
            emit_css_box(wid, fg=R(sec.get("label-foreground")), bg=R(sec.get("format-background")))
        elif t in ("internal/cpu",):
            mod = {"format": strip_action(sec.get("label", "{usage}%")).replace("%percentage%", "{usage}"),
                   "interval": 2, "tooltip": False}
            emit_css_box(wid, fg=R(sec.get("label-foreground")), bg=R(sec.get("format-background")))
        elif t == "internal/backlight":
            mod = {"format": strip_action(sec.get("label", "{percent}%")).replace("%percentage%", "{percent}"),
                   "tooltip": False}
            emit_css_box(wid, fg=R(sec.get("label-foreground")), bg=R(sec.get("format-background")))
        elif t == "internal/tray":
            sp = re.sub(r"\D", "", sec.get("tray-spacing", "6")) or "6"
            mod = {"spacing": int(sp)}
            emit_css_box(wid, bg=R(sec.get("format-background")),
                         ul=R(sec.get("format-underline")), ol=R(sec.get("format-overline")))
        elif t == "custom/text":
            # static decoration / powerline cap: label with fg/bg -> static custom module
            label = strip_action(sec.get("label", ""))
            mod = {"format": label, "tooltip": False}
            clicks(sec, mod)
            emit_css_box(wid, fg=R(sec.get("label-foreground")),
                         bg=R(sec.get("format-background") or sec.get("label-background")),
                         ul=R(sec.get("label-underline")), ol=R(sec.get("label-overline")),
                         font_slot=sec.get("label-font"))
        elif t == "custom/script":
            exec_ = sec.get("exec", "")
            # keep env-prefixed exec lines intact; waybar runs them via sh -c
            mod = {"exec": R(exec_).strip(), "format": "{}", "tooltip": False}
            if sec.get("tail", "").lower() == "true":
                mod["exec"] = R(exec_).strip()  # script loops itself
            else:
                try:
                    mod["interval"] = int(sec.get("interval", "5"))
                except ValueError:
                    mod["interval"] = 5
            clicks(sec, mod)
            # The polybar media widget carried its prev/play-pause/next as inline
            # %{A} click zones (stripped in the ported script); re-add them as
            # waybar button actions if the module itself declares none.
            if "polybar-media" in mod["exec"]:
                mod.setdefault("on-click", "playerctl play-pause")
                mod.setdefault("on-click-right", "playerctl next")
                mod.setdefault("on-click-middle", "playerctl previous")
            emit_css_box(wid, fg=R(sec.get("label-foreground")), bg=R(sec.get("format-background")))
        else:
            # unknown (bspwm/ipc/etc.) -> best-effort custom passthrough
            if sec.get("exec"):
                mod = {"exec": R(sec.get("exec")).strip(), "format": "{}", "tooltip": False}
                clicks(sec, mod)
            else:
                mod = {"format": strip_action(sec.get("label", "")), "tooltip": False}
        used_ids.append(wid)
        return wid, mod

    def build_side(names):
        ids = []
        for n in names:
            res = handle(n)
            if res is None:
                continue
            wid, mod = res
            # dedupe id collisions (e.g. two sep modules mapping to same name won't happen; names unique)
            waybar.setdefault("_defs", {})[wid] = mod
            ids.append(wid)
        return ids

    waybar["modules-left"] = build_side(left)
    waybar["modules-center"] = build_side(center)
    waybar["modules-right"] = build_side(right)
    defs = waybar.pop("_defs", {})
    out = {k: v for k, v in waybar.items()}
    for wid, mod in defs.items():
        out[wid] = mod

    (outdir / "config.jsonc").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (outdir / "style.css").write_text("\n".join(css) + "\n", encoding="utf-8")
    print(f"{src.stem}: {len(waybar['modules-left'])}L/{len(waybar['modules-center'])}C/{len(waybar['modules-right'])}R modules -> {outdir}")

if __name__ == "__main__":
    main()
