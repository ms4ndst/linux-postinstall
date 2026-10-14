#!/usr/bin/env python3
"""Drive the repo's generate-gtk/nvim/vscode-themes.py for EVERY theme
currently installed in ~/.config/polybar/themes - the HANCORE themes'
[colors] blocks written by hancore-theme-gen.py, plus any of the rice's
own themes the user kept (they live in the same place, same format) -
instead of those generators' hardcoded THEMES lists.

Light themes (base color luminance > 0.5, none of the HANCORE set is
light today but the check is cheap) are collected the way the generators
expect LIGHT_THEMES.

Usage: rice-gen-driver.py <repo-dir-containing-the-generators>
"""
import configparser
import glob
import importlib.util
import os
import sys

repo = sys.argv[1]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def luminance(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def main():
    themes_dir = os.path.expanduser("~/.config/polybar/themes")
    names = sorted(os.path.basename(p)[:-4]
                   for p in glob.glob(os.path.join(themes_dir, "*.ini")))
    if not names:
        print("rice-gen-driver: no themes in %s, nothing to do" % themes_dir)
        return 0

    light = set()
    for n in names:
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(os.path.join(themes_dir, "%s.ini" % n))
        if parser.has_section("colors") and luminance(parser["colors"]["base"]) > 0.5:
            light.add(n)
    print("rice-gen-driver: %d themes (%d light)" % (len(names), len(light)))

    for gen in ("generate-vscode-themes.py", "generate-gtk-themes.py",
                "generate-nvim-themes.py"):
        path = os.path.join(repo, gen)
        if not os.path.isfile(path):
            print("rice-gen-driver: %s not found, skipping" % gen)
            continue
        mod = load(path, gen.replace("-", "_"))
        mod.THEMES = names
        if hasattr(mod, "LIGHT_THEMES"):
            mod.LIGHT_THEMES = light
        if hasattr(mod, "_vscode_gen"):
            # generate-gtk/nvim re-exec generate-vscode-themes.py as their
            # shared color-resolution module - patch that copy too, since
            # the GTK generator reads LIGHT_THEMES from it at call time.
            mod._vscode_gen.THEMES = names
            mod._vscode_gen.LIGHT_THEMES = light
        print("=== %s" % gen)
        mod.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
