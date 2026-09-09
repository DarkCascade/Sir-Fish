#!/usr/bin/env python3
"""Audit the palette and type scale for small-screen, low-light legibility.

Built for the art-style exploration (`design documents/Art Direction/`). The
complaint that started it: "the colour scheme is too dark and the text is too
small to read on my phone at night." Measuring that complaint turned up
something the naive reading misses — **text contrast is not the problem**.
Every text-on-panel pair in the shipped palette clears WCAG AA comfortably
(C_TEXT on C_CONSOLE_PANEL is 13.45:1). Two other things fail instead:

1. **Luminance-range compression.** 11 of the 15 world + chrome colours sit
   below 0.05 relative luminance, so panel-vs-background separation is
   1.20:1, inset-vs-background 1.06:1, near-trees-vs-console 1.05:1. On a
   phone at low brightness with any ambient glare, everything under ~0.05
   collapses into one undifferentiated black mass. You cannot read the
   *layout*, never mind the text.
2. **Sub-pixel structure.** All that separation is carried by 3-4 px borders
   authored against a 1080-wide viewport. On a 390 px-wide phone that is
   1.1-1.4 CSS px — a hairline, and the first thing a mobile GPU's filtering
   eats.

Type size is a real but secondary issue: 34 px body against a 1080 design
width is 12.3 CSS px on a 390 px phone, set in EB Garamond at weight 400 —
an old-style serif whose hairline strokes and small x-height are the worst
possible combination at that size.

So this script measures the three things that actually matter — luminance
distribution, structural separation, and effective type size in CSS pixels —
rather than only the WCAG ratios that already pass.

Usage:
    python tools/palette_audit.py                    # audit as shipped
    python tools/palette_audit.py --profile lantern  # gate against a style
    python tools/palette_audit.py --strict           # exit 1 on any failure

Profiles correspond to the art-style specs in `design documents/Art
Direction/`. `--strict` is what a CI step or an implementing model should
run: it turns the report into a pass/fail gate.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TUNING = REPO / "scripts" / "autoload" / "tuning.gd"
THEME = REPO / "assets" / "theme.tres"

# The design-space viewport width from project.godot (window/size/viewport_width).
# Every font size and border width in the project is authored against this, and
# `window/stretch/mode="canvas_items"` scales it to whatever the device gives us.
DESIGN_WIDTH = 1080

# Two representative phones. 390 is an iPhone 14/15-class CSS width, 412 a
# common Android one. Both are portrait, which is the only orientation the
# project ships (window/handheld/orientation=1).
PHONE_WIDTHS = (390, 412)

# Adjacency pairs that carry the layout, split by kind.
#
# CHROME pairs are UI edges: two surfaces of the frame that physically touch,
# where a missing edge means you cannot tell where a panel ends. WORLD pairs
# are depth layers in the 3D scene, and they get a lower floor for a reason
# that is arithmetic, not taste: a ratio of R between every adjacent pair of a
# 5-layer stack needs the top layer to sit at roughly R^4 times the bottom
# one's offset luminance, so demanding 3:1 per step makes a 5-layer stack
# impossible to author at all. Depth reads from *consistent* steps, not
# maximal ones; UI edges need the hard step.
CHROME_PAIRS_DEFAULT = [
    ("C_CONSOLE_PANEL", "C_CONSOLE_BG", "panel against the screen behind it"),
    ("C_CONSOLE_INSET", "C_CONSOLE_PANEL", "well punched into a panel"),
    ("C_PANEL_BORDER", "C_CONSOLE_PANEL", "border on its own panel"),
    ("C_CONSOLE_STONE", "C_CONSOLE_BG", "carved frame against the screen"),
    ("C_RELIQUARY_STONE", "C_RELIQUARY_MIST", "modal tablet against its scrim"),
]
WORLD_PAIRS_DEFAULT = [
    ("C_NEAR_TREES", "C_CONSOLE_BG", "world's darkest layer vs the console"),
    ("C_BRUSH", "C_NEAR_TREES", "undergrowth against near trunks"),
]
# Storybook is opaque poster layers: the console is a solid card, so the
# recessed well never touches the raw background, and the world reads as a
# stack of flat plates rather than as haze over a void.
WORLD_PAIRS_POSTER = [
    ("C_MID_TREES", "C_NEAR_TREES", "mid canopy against near trunks"),
    ("C_FAR_HILLS", "C_MID_TREES", "treeline against mid canopy"),
    ("C_SKY", "C_FAR_HILLS", "sky against the treeline"),
    ("C_GROUND", "C_BRUSH", "lit path against undergrowth"),
]

# Text-on-surface pairs. Mostly pass today; measured because any restyle can
# break them, and because lifting panels to fix structure is exactly the move
# that quietly ruins the text sitting on those panels.
TEXT_PAIRS_DEFAULT = [
    ("C_TEXT", "C_CONSOLE_PANEL", 4.5),
    ("C_TEXT", "C_CONSOLE_BG", 4.5),
    ("C_TEXT_DIM", "C_CONSOLE_INSET", 4.5),
    ("C_TEXT_GOLD", "C_CONSOLE_PANEL", 3.0),
    ("C_TEXT", "C_RELIQUARY_STONE", 4.5),
    ("C_CRYSTAL_BRIGHT", "C_RELIQUARY_STONE", 4.5),
]

# Storybook inverts text polarity — dark ink on light paper — so its text sits
# on different surfaces entirely. Secondary text never lands in the recessed
# well there (the well is a mid-value blue plate, not a dark hole).
TEXT_PAIRS_POSTER = [
    ("C_TEXT", "C_CONSOLE_PANEL", 4.5),
    ("C_TEXT", "C_CONSOLE_STONE", 4.5),
    ("C_TEXT_DIM", "C_CONSOLE_PANEL", 4.5),
    ("C_TEXT_GOLD", "C_CONSOLE_PANEL", 3.0),
    ("C_TEXT", "C_RELIQUARY_STONE", 4.5),
    ("C_CRYSTAL_BRIGHT", "C_RELIQUARY_STONE", 4.5),
]

# Colours that belong to the world (lit 3D) rather than the frame (unshaded
# UI). Kept apart because §6.1's organising rule — "cool blue is the light,
# green is the ground, gold is the UI" — means the two halves are allowed,
# and expected, to occupy different parts of the luminance range.
WORLD_KEYS = {
    "C_SKY", "C_FAR_HILLS", "C_MID_TREES", "C_NEAR_TREES",
    "C_GROUND", "C_BRUSH", "C_ROCK",
}

# Chrome splits three ways, and the distinction is what makes the dark-surface
# metric mean anything:
#   SURFACE  things drawn ON the screen, which must be legible as objects.
#   EDGE     borders and shadow lines. Free to be near-black — in a poster
#            style a heavy ink outline IS the design — so they are exempt.
#   VOID     the background behind everything, and scrims. Supposed to be
#            dark; that is their entire job. Also exempt.
CHROME_SURFACE_KEYS = {
    "C_CONSOLE_PANEL", "C_CONSOLE_INSET", "C_CONSOLE_STONE", "C_RELIQUARY_STONE",
}
CHROME_EDGE_KEYS = {"C_PANEL_BORDER", "C_RELIQUARY_STONE_DARK"}
CHROME_VOID_KEYS = {"C_CONSOLE_BG", "C_RELIQUARY_MIST"}
CHROME_KEYS = CHROME_SURFACE_KEYS | CHROME_EDGE_KEYS | CHROME_VOID_KEYS


class Profile:
    """A readability floor. Each art-style spec gates against one of these."""

    def __init__(self, name, min_structural, min_tier_gap, min_css_px,
                 min_border_css_px, max_dark_fraction, description,
                 min_world=1.8, chrome_pairs=None, world_pairs=None,
                 text_pairs=None):
        self.name = name
        self.min_world = min_world
        self.chrome_pairs = chrome_pairs or CHROME_PAIRS_DEFAULT
        self.world_pairs = world_pairs if world_pairs is not None else WORLD_PAIRS_DEFAULT
        self.text_pairs = text_pairs or TEXT_PAIRS_DEFAULT
        # Minimum WCAG-style ratio between two surfaces that touch. 1.5:1 is
        # roughly where an edge stops being visible at phone brightness; 2.0
        # is comfortable; 3.0 reads as a deliberate tier change.
        self.min_structural = min_structural
        # Minimum luminance delta between the three chrome tiers (well,
        # panel, raised frame). Ratios alone hide the fact that everything is
        # crammed into the bottom of the range.
        self.min_tier_gap = min_tier_gap
        self.min_css_px = min_css_px
        self.min_border_css_px = min_border_css_px
        # Fraction of chrome colours allowed below 0.05 luminance.
        self.max_dark_fraction = max_dark_fraction
        self.description = description


PROFILES = {
    # What ships today. Thresholds set to the shipped values so the audit
    # reports without failing — this profile documents the baseline, it does
    # not endorse it.
    "current": Profile(
        "current", min_structural=1.0, min_tier_gap=0.0, min_css_px=0.0,
        min_border_css_px=0.0, max_dark_fraction=1.0, min_world=1.0,
        description="Baseline measurement of the shipped look. Never a gate.",
    ),
    # Art Style A. Stays dark — night play on an OLED phone is the actual use
    # case — but redistributes the range so structure survives.
    "lantern": Profile(
        "lantern", min_structural=2.0, min_tier_gap=0.045, min_css_px=14.0,
        min_border_css_px=2.5, max_dark_fraction=0.34, min_world=1.8,
        description="High-contrast night. Dark stays, but panels lift into a "
                    "real mid-tone and every edge carries weight.",
    ),
    # Art Style B. Flat poster colour, so separation is generous by
    # construction and the floor can be stricter.
    "storybook": Profile(
        "storybook", min_structural=3.0, min_tier_gap=0.08, min_css_px=15.0,
        min_border_css_px=3.0, max_dark_fraction=0.15, min_world=1.8,
        world_pairs=WORLD_PAIRS_POSTER, text_pairs=TEXT_PAIRS_POSTER,
        description="Flat illustrated poster. Every element is its own value "
                    "block with a heavy ink outline.",
    ),
}


def srgb_to_linear(channel: int) -> float:
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_str: str) -> float:
    """WCAG relative luminance, 0.0 (black) to 1.0 (white)."""
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return (0.2126 * srgb_to_linear(r)
            + 0.7152 * srgb_to_linear(g)
            + 0.0722 * srgb_to_linear(b))


def contrast(hex_a: str, hex_b: str) -> float:
    la, lb = luminance(hex_a), luminance(hex_b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def parse_palette(path: Path) -> dict[str, str]:
    """Pull every `const C_NAME := Color("RRGGBB")` out of tuning.gd.

    Deliberately ignores Color(r, g, b, a) float constructors: the palette
    block (§6.1) is authored as hex strings throughout, and a float-tuple
    match here would also drag in unrelated per-script tints.
    """
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(r'const\s+(C_\w+)\s*:=\s*Color\("([0-9A-Fa-f]{6})"\)')
    return {m.group(1): m.group(2).upper() for m in pattern.finditer(text)}


def parse_theme(path: Path) -> tuple[dict[str, int], list[int]]:
    """Return theme font sizes by key, plus every border width found."""
    text = path.read_text(encoding="utf-8")
    sizes: dict[str, int] = {}
    for m in re.finditer(r'^(default_font_size|[\w/]*font_sizes?/font_size)\s*=\s*(\d+)',
                         text, re.MULTILINE):
        sizes[m.group(1)] = int(m.group(2))
    borders = [int(m.group(1)) for m in
               re.finditer(r'^border_width_\w+\s*=\s*(\d+)', text, re.MULTILINE)]
    return sizes, borders


def scan_font_sizes(repo: Path) -> dict[int, int]:
    """Count font sizes used across scenes and scripts.

    Covers both authoring routes: `theme_override_font_sizes/font_size = N`
    in .tscn files, and `add_theme_font_size_override("font_size", N)` in
    GDScript. Anything the theme does not set is set in one of these two ways.
    """
    counts: dict[int, int] = {}
    patterns = [
        re.compile(r'theme_override_font_sizes/font_size\s*=\s*(\d+)'),
        re.compile(r'add_theme_font_size_override\(\s*["\']font_size["\']\s*,\s*(\d+)'),
        re.compile(r'font_sizes?/font_size\s*=\s*(\d+)'),
    ]
    for sub in ("scenes", "scripts"):
        root = repo / sub
        if not root.is_dir():
            continue
        for file in list(root.rglob("*.tscn")) + list(root.rglob("*.gd")):
            try:
                body = file.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for pat in patterns:
                for m in pat.finditer(body):
                    size = int(m.group(1))
                    counts[size] = counts.get(size, 0) + 1
    return counts


def css_px(design_px: float, phone_width: int) -> float:
    """Design-space pixels as they land on a phone, under canvas_items stretch."""
    return design_px * phone_width / DESIGN_WIDTH


def bar(value: float, width: int = 60, scale: float = 1.0) -> str:
    filled = max(1, int(round(value * width / scale)))
    return "#" * min(filled, width)


def report(profile: Profile) -> bool:
    palette = parse_palette(TUNING)
    theme_sizes, borders = parse_theme(THEME)
    used_sizes = scan_font_sizes(REPO)
    failures: list[str] = []

    print(f"Sir Fish — palette & type audit")
    print(f"profile: {profile.name} — {profile.description}")
    print(f"design viewport: {DESIGN_WIDTH}px wide (portrait)")
    print(f"palette constants parsed: {len(palette)}")
    print()

    # --- 1. luminance distribution -------------------------------------------
    print("=" * 78)
    print("1. LUMINANCE DISTRIBUTION — where the image actually sits")
    print("=" * 78)
    tracked = {k: v for k, v in palette.items()
               if k in WORLD_KEYS or k in CHROME_KEYS
               or k.startswith(("C_TEXT", "C_GOLD", "C_CRYSTAL_BRIGHT"))}
    for key, hexv in sorted(tracked.items(), key=lambda kv: luminance(kv[1])):
        lum = luminance(hexv)
        tag = "world " if key in WORLD_KEYS else ("chrome" if key in CHROME_KEYS else "text  ")
        print(f"  {lum:6.4f}  #{hexv}  {tag}  {key:26s} {bar(lum)}")

    # Only true SURFACES are gated. Edges (borders, shadow lines) and voids
    # (screen background, modal scrim) are supposed to be dark, so counting
    # them would punish a poster style for having a heavy ink outline.
    surfaces = {k: v for k, v in palette.items() if k in CHROME_SURFACE_KEYS}
    dark_surfaces = [k for k, v in surfaces.items() if luminance(v) < 0.05]
    frac = len(dark_surfaces) / len(surfaces) if surfaces else 0.0
    print()
    print(f"  chrome SURFACES below 0.05 luminance: {len(dark_surfaces)}/{len(surfaces)} "
          f"({frac:.0%}) — max is {profile.max_dark_fraction:.0%}")
    print(f"  (edges {sorted(CHROME_EDGE_KEYS)} and voids {sorted(CHROME_VOID_KEYS)} exempt "
          f"— they are meant to be dark)")
    if frac > profile.max_dark_fraction:
        failures.append(
            f"{frac:.0%} of chrome surfaces sit below 0.05 luminance (max "
            f"{profile.max_dark_fraction:.0%}). At phone brightness these are one black "
            f"mass: {', '.join(sorted(dark_surfaces))}")

    # Tier separation: the three chrome depths must be genuinely distinct.
    tiers = [("well", "C_CONSOLE_INSET"), ("panel", "C_CONSOLE_PANEL"),
             ("frame", "C_CONSOLE_STONE")]
    have = [(name, palette[key]) for name, key in tiers if key in palette]
    if len(have) == 3:
        print()
        print("  chrome tiers (well -> panel -> raised frame):")
        for i in range(len(have) - 1):
            (an, av), (bn, bv) = have[i], have[i + 1]
            gap = abs(luminance(bv) - luminance(av))
            ok = "ok" if gap >= profile.min_tier_gap else "FAIL"
            print(f"    {an:6s} {luminance(av):.4f} -> {bn:6s} {luminance(bv):.4f}"
                  f"   delta {gap:.4f}  (floor {profile.min_tier_gap:.4f})  {ok}")
            if gap < profile.min_tier_gap:
                failures.append(
                    f"chrome tier gap {an}->{bn} is {gap:.4f}, floor is "
                    f"{profile.min_tier_gap:.4f} — the depth read is not survivable on a phone")

    # --- 2. structural separation --------------------------------------------
    print()
    print("=" * 78)
    print("2. STRUCTURAL SEPARATION — can you see where a panel ends?")
    print("=" * 78)
    for kind, pairs, floor in (("chrome", profile.chrome_pairs, profile.min_structural),
                               ("world ", profile.world_pairs, profile.min_world)):
        for a, b, why in pairs:
            if a not in palette or b not in palette:
                continue
            ratio = contrast(palette[a], palette[b])
            ok = "ok" if ratio >= floor else "FAIL"
            note = "  <- invisible edge" if ratio < 1.5 else ""
            print(f"  [{kind}] {ratio:5.2f}:1 (floor {floor:.1f})  {ok:4s}  "
                  f"{a:20s} vs {b:20s}  {why}{note}")
            if ratio < floor:
                failures.append(
                    f"{a} vs {b} is {ratio:.2f}:1, floor is {floor:.2f}:1 — {why}")

    # --- 3. text on surface ---------------------------------------------------
    print()
    print("=" * 78)
    print("3. TEXT ON SURFACE — each pair against the level it must clear")
    print("=" * 78)
    for a, b, required in profile.text_pairs:
        if a not in palette or b not in palette:
            continue
        ratio = contrast(palette[a], palette[b])
        level = "AA" if ratio >= 4.5 else ("AA-large" if ratio >= 3.0 else "FAIL")
        ok = "ok" if ratio >= required else "FAIL"
        print(f"  {ratio:5.2f}:1  {level:9s} needs {required:.1f}  {ok:4s}  {a:18s} on {b}")
        if ratio < required:
            failures.append(
                f"{a} on {b} is {ratio:.2f}:1, needs {required:.1f}:1")

    # --- 4. type scale --------------------------------------------------------
    print()
    print("=" * 78)
    print("4. TYPE SCALE — design pixels as they land on a phone")
    print("=" * 78)
    print(f"  theme keys:")
    for key, size in sorted(theme_sizes.items(), key=lambda kv: -kv[1]):
        landed = [f"{css_px(size, w):.1f}" for w in PHONE_WIDTHS]
        print(f"    {size:3d}px  ->  {' / '.join(landed)} CSS px   {key}")

    if used_sizes:
        smallest = min(used_sizes)
        print(f"\n  sizes used across scenes/scripts ({sum(used_sizes.values())} declarations, "
              f"{len(used_sizes)} distinct):")
        for size in sorted(used_sizes, reverse=True):
            landed = css_px(size, PHONE_WIDTHS[0])
            flag = "  <- below floor" if landed < profile.min_css_px else ""
            print(f"    {size:3d}px x{used_sizes[size]:<3d} ->  {landed:5.1f} CSS px @390{flag}")
        worst = css_px(smallest, PHONE_WIDTHS[0])
        print(f"\n  smallest type: {smallest}px design -> {worst:.1f} CSS px on a 390px phone "
              f"(floor {profile.min_css_px:.0f})")
        if worst < profile.min_css_px:
            offenders = sorted(s for s in used_sizes
                               if css_px(s, PHONE_WIDTHS[0]) < profile.min_css_px)
            failures.append(
                f"smallest type lands at {worst:.1f} CSS px, floor is {profile.min_css_px:.0f} — "
                f"design sizes below floor: {offenders}")

    # --- 5. border weight -----------------------------------------------------
    print()
    print("=" * 78)
    print("5. BORDER WEIGHT — the hairlines carrying all the structure")
    print("=" * 78)
    if borders:
        distinct = sorted(set(borders))
        for w in distinct:
            landed = css_px(w, PHONE_WIDTHS[0])
            flag = "  <- sub-pixel on a phone" if landed < profile.min_border_css_px else ""
            print(f"    {w}px design x{borders.count(w):<3d} ->  {landed:4.2f} CSS px @390{flag}")
        thinnest = css_px(min(distinct), PHONE_WIDTHS[0])
        if thinnest < profile.min_border_css_px:
            failures.append(
                f"thinnest border lands at {thinnest:.2f} CSS px, floor is "
                f"{profile.min_border_css_px:.1f} — mobile filtering eats it")

    # --- verdict --------------------------------------------------------------
    print()
    print("=" * 78)
    if profile.name == "current":
        print("BASELINE — 'current' never fails; it records what ships today.")
        print("=" * 78)
        return True
    if failures:
        print(f"FAIL — {len(failures)} finding(s) against profile '{profile.name}'")
        print("=" * 78)
        for i, f in enumerate(failures, 1):
            print(f"  {i}. {f}")
        return False
    print(f"PASS — profile '{profile.name}' satisfied")
    print("=" * 78)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit palette and type scale for phone/low-light legibility.")
    parser.add_argument("--profile", choices=sorted(PROFILES), default="current",
                        help="readability floor to gate against (default: current)")
    parser.add_argument("--strict", action="store_true",
                        help="exit 1 if the profile is not satisfied")
    args = parser.parse_args()

    if not TUNING.exists():
        print(f"error: {TUNING} not found — run from the repo root", file=sys.stderr)
        return 2

    ok = report(PROFILES[args.profile])
    return 0 if ok or not args.strict else 1


if __name__ == "__main__":
    sys.exit(main())
