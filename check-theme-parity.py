#!/usr/bin/env python3
"""Guard: the Catppuccin Mocha color model must stay identical between the two
independent copies that theme the desktop.

  - sway-build/hancore-theme-gen.py  -> Wayland bar/app theming (Waybar, rofi,
                                        dunst, kitty, Starship, GTK via HANCORE)
  - generate-gtk-themes.py           -> GTK/libadwaita app theming

Each file carries its OWN copy of the 26-role CANONICAL_MOCHA palette, the
NEUTRAL_ROLES set, and the nearest-role classifier constants (achromatic
threshold + the hue/saturation distance weights). There is no shared import, so
nothing else keeps them in lockstep. If one copy is edited and the other is not,
the same hex would be classified to a different role and Waybar vs GTK apps would
silently theme the same color inconsistently.

This script does NOT de-duplicate the code (that would mean a shared colors.py,
which has to cross the sway-build/ heredoc-embedding boundary). It only fails
loudly the moment the two copies drift, turning a silent risk into a clear error.

It is pure stdlib and has NO side effects: it parses both files via AST and never
imports them (importing generate-gtk-themes.py would dynamically load the VS Code
generator and touch the theme dirs). Run it from anywhere.

Exit 0 if the two copies agree, 1 (with a diff) otherwise.
"""
import ast
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
HANCORE = HERE / "sway-build" / "hancore-theme-gen.py"
GTK = HERE / "generate-gtk-themes.py"


def _tree(path):
    return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


def literal_assign(tree, name):
    """Value of a module-level `name = <literal>` assignment, via literal_eval."""
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == name for t in node.targets
        ):
            return ast.literal_eval(node.value)
    raise KeyError(f"{name} not found as a module-level assignment")


def find_func(tree, *names):
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name in names:
            return node
    raise KeyError(f"none of {names} found as a function")


def classifier_constants(func):
    """Pull the three tuning constants out of a classifier function body:
    the achromatic threshold `s < N`, and the weights in
    `hue_dist(...) * W1 + abs(l - cl) + abs(s - cs) * W2`."""
    consts = {"achromatic_threshold": None, "hue_weight": None, "sat_weight": None}
    for n in ast.walk(func):
        if (
            isinstance(n, ast.Compare)
            and isinstance(n.left, ast.Name)
            and n.left.id == "s"
            and len(n.ops) == 1
            and isinstance(n.ops[0], ast.Lt)
            and isinstance(n.comparators[0], ast.Constant)
        ):
            consts["achromatic_threshold"] = n.comparators[0].value
        if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Mult):
            for a, b in ((n.left, n.right), (n.right, n.left)):
                if (
                    isinstance(a, ast.Call)
                    and isinstance(a.func, ast.Name)
                    and isinstance(b, ast.Constant)
                ):
                    if a.func.id == "hue_dist":
                        consts["hue_weight"] = b.value
                    elif a.func.id == "abs":
                        consts["sat_weight"] = b.value
    return consts


def main():
    problems = []
    for p in (HANCORE, GTK):
        if not p.is_file():
            print(f"ERROR: expected file not found: {p}", file=sys.stderr)
            return 2

    ht, gt = _tree(HANCORE), _tree(GTK)

    # 1. CANONICAL_MOCHA palette (role -> hex), case-insensitive on the hex.
    hm = {k: v.lower() for k, v in literal_assign(ht, "CANONICAL_MOCHA").items()}
    gm = {k: v.lower() for k, v in literal_assign(gt, "CANONICAL_MOCHA").items()}
    if hm != gm:
        only_h = {k: hm[k] for k in hm.keys() - gm.keys()}
        only_g = {k: gm[k] for k in gm.keys() - hm.keys()}
        changed = {k: (hm[k], gm[k]) for k in hm.keys() & gm.keys() if hm[k] != gm[k]}
        problems.append(
            "CANONICAL_MOCHA differs:\n"
            + (f"    only in hancore: {only_h}\n" if only_h else "")
            + (f"    only in gtk:     {only_g}\n" if only_g else "")
            + (f"    role hex changed (hancore, gtk): {changed}\n" if changed else "")
        )

    # 2. NEUTRAL_ROLES set.
    hn = set(literal_assign(ht, "NEUTRAL_ROLES"))
    gn = set(literal_assign(gt, "NEUTRAL_ROLES"))
    if hn != gn:
        problems.append(
            f"NEUTRAL_ROLES differs:\n    only hancore: {hn - gn}\n    only gtk: {gn - hn}\n"
        )

    # 3. Classifier tuning constants.
    hc = classifier_constants(find_func(ht, "classify"))
    gc = classifier_constants(find_func(gt, "classify_color"))
    if hc != gc:
        diff = {k: (hc[k], gc[k]) for k in hc if hc[k] != gc[k]}
        problems.append(f"classifier constants differ (hancore, gtk): {diff}\n")
    for who, c in (("hancore", hc), ("gtk", gc)):
        missing = [k for k, v in c.items() if v is None]
        if missing:
            problems.append(
                f"could not extract {missing} from {who}'s classifier "
                f"(the formula shape changed - update this check)\n"
            )

    if problems:
        print("THEME PALETTE DRIFT between the two Mocha color models:\n")
        for pr in problems:
            print("  - " + pr.rstrip() + "\n")
        print(
            f"Reconcile {HANCORE.name} and {GTK.name} (26-role palette, neutral\n"
            "roles, and classifier constants must match), then re-run this check."
        )
        return 1

    print(
        f"OK: Mocha color model is in sync across {HANCORE.name} and {GTK.name}\n"
        f"    ({len(hm)} roles, {len(hn)} neutral, constants {hc})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
