#!/usr/bin/env python3
"""Draws a pack's tile for the game library (docs/packs/format.md, `ui/tile`): its menu picture cut to
750x300 and darkened behind a plain title, the pack's English name in Classic's title font (Alegreya SC)
with the year under it; a pack with its own logo (manifest `logo`, light on black) gets that instead of
the name. Needs ImageMagick (`magick`).

Usage: python3 tools/pack_tile.py packs/loot [packs/gvg …]   (writes packs/<name>/ui/tile.jpg)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "packs/classic/ui/fonts/AlegreyaSC-ExtraBold.ttf"
W, H = 750, 300
GOLD, EDGE = "#f6d27a", "#2a1606"


def menu_picture(pack: Path) -> Path:
    for p in [pack / f"ui/menu.{e}" for e in ("jpg", "png", "webp")] + [pack / "art/default/menu.jpg"]:
        if p.exists():
            return p
    raise SystemExit(f"{pack}: no menu picture (ui/menu.* or art/default/menu.jpg)")


def logo(pack: Path) -> Path | None:
    """The pack's own logo picture (in ui/, or where its recipe moves it from: art/default/), or None."""
    f = json.loads((pack / "manifest.json").read_text()).get("logo")
    if not isinstance(f, str):
        return None
    return next((p for p in (pack / f, pack / "art/default" / Path(f).name) if p.exists()), None)


def title(pack: Path) -> tuple[str, str]:
    """The English name and its year apart ("Kobolds & Catacombs", "2017"); no year: ""."""
    name = json.loads((pack / "manifest.json").read_text()).get("name")
    if name is None:  # (a pack whose name is only in its locales)
        name = json.loads((pack / "locales/en.json").read_text())["pack"]["name"]
    name = name.get("en") or next(iter(name.values())) if isinstance(name, dict) else str(name)
    m = re.fullmatch(r"(.*?)\s+((?:19|20)\d\d)", name.strip())
    return (m.group(1), m.group(2)) if m else (name.strip(), "")


def draw(pack: Path) -> Path:
    name, year = title(pack)
    out = pack / "ui/tile.jpg"
    own = logo(pack)
    if own:
        subprocess.run(["magick", str(menu_picture(pack)), "-resize", f"{W}x{H}^", "-gravity", "center", "-extent", f"{W}x{H}",
                        "(", str(own), "-resize", f"{W}x{H}^", "-gravity", "center", "-extent", f"{W}x{H}", ")",
                        "-compose", "screen", "-composite", "-quality", "88", str(out)], check=True)
        return out
    text_y = -18 if year else 0
    cmd = ["magick", str(menu_picture(pack)), "-resize", f"{W}x{H}^", "-gravity", "center", "-extent", f"{W}x{H}",
           # a soft dark plate behind the title
           "(", "-size", f"{W}x{H}", "xc:none", "-fill", "rgba(0,0,0,0.55)", "-draw", "roundrectangle 50,62 700,238 60,60",
           "-blur", "0x28", ")", "-compose", "over", "-composite",
           # the name: as big as fits 660x100, gold with a dark rim and a shadow
           "(", "-background", "none", "-font", str(FONT), "-fill", GOLD, "-stroke", EDGE, "-strokewidth", "3",
           "-size", "660x100", "-gravity", "center", f"label:{name}",
           "(", "+clone", "-background", "black", "-shadow", "85x5+0+3", ")", "+swap", "-background", "none",
           "-layers", "merge", "+repage", ")",
           "-gravity", "center", "-geometry", f"+0{text_y:+d}", "-compose", "over", "-composite"]
    if year:
        cmd += ["-font", str(FONT), "-pointsize", "38", "-fill", GOLD, "-stroke", EDGE, "-strokewidth", "2",
                "-gravity", "center", "-annotate", "+0+52", year,
                "-stroke", GOLD, "-strokewidth", "2", "-draw", "line 255,202 320,202", "-draw", "line 430,202 495,202"]
    cmd += ["-quality", "88", str(out)]
    subprocess.run(cmd, check=True)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for a in sys.argv[1:]:
        print(draw(Path(a)))
