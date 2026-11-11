#!/usr/bin/env python3
"""Paints a pack's interface pictures in its set's theme with the local Codex CLI (as Naxxramas's and
Neonfall's were made): ui/menu, ui/board, ui/library, ui/result_victory, ui/result_defeat, ui/result_draw
(docs/packs/format.md §1), 1280x720 JPEG, one Codex run for all six.

Usage: python3 tools/pack_backgrounds.py packs/gvg --theme "Goblins vs Gnomes: a goblin workshop full of …"
                                         [--only menu board] [--no-guard]
Existing pictures are kept (delete one to paint it again). tools/codex_guard.sh watches the weekly Codex limit
meanwhile and stops the run at 90 % used (--no-guard: not). CODEX overrides the Codex binary.
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

CODEX = os.environ.get("CODEX", "/Applications/ChatGPT.app/Contents/Resources/codex")
ROOT = Path(__file__).resolve().parent.parent

STYLE = ("Painterly fantasy digital illustration in the warm, chunky, hand-painted look of a classic fantasy card game's "
         "boards and menus (an original design: do not copy any existing game's art, logo or characters). Rich lighting, "
         "readable shapes, a calm area where the interface sits. Absolutely no text, letters, numbers, logos, UI, card "
         "frames, borders or watermarks.")
# name -> what to paint (the theme is added to each)
PICTURES = {
    "menu": "the game's main menu backdrop: a sweeping, inviting view of the theme's most iconic place, the centre left "
            "a little calmer for the menu buttons",
    "board": "a game board seen from straight above: a wide wooden or stone table surface in the theme, ornate edges and "
             "props around the rim, a large plain calm area in the middle for the cards",
    "library": "the collection screen backdrop: a cosy room of the theme with shelves and treasures, softly lit, not busy",
    "result_victory": "the moment of victory in the theme: a triumphant, bright, celebratory scene",
    "result_defeat": "the moment of defeat in the theme: a dark, sombre, broken scene",
    "result_draw": "a draw in the theme: two equal forces in balance, a quiet standoff",
}


def finish(src, dst):
    """Crops to 16:9 (centre) and scales to 1280x720, a JPEG of quality 82."""
    r = subprocess.run(["magick", str(src), "-resize", "1280x720^", "-gravity", "center", "-extent", "1280x720",
                        "-strip", "-quality", "82", str(dst)], capture_output=True)
    return r.returncode == 0 and dst.exists()


def paint(ui, theme, names):
    work = ROOT / "build" / "pack_backgrounds" / ui.parent.name
    (work / "out").mkdir(parents=True, exist_ok=True)
    lines = "\n".join(f"- ID {n} (landscape 16:9): {PICTURES[n]}" for n in names)
    prompt = (f"Use your built-in image generation tool (not code, not other tools) to create {len(names)} images, one "
              "per entry listed below, in the given order, each landscape 16:9.\n"
              f"{STYLE}\nThe theme of every image: {theme}\n"
              "After generating each image, copy the generated PNG file to ./out/<ID>.png (use the exact ID). "
              "Do not create any other files. Entries:\n" + lines)
    t0 = time.time()
    r = subprocess.run([CODEX, "exec", "--skip-git-repo-check", "--ephemeral", "-s", "workspace-write", "-C", str(work), prompt],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=3600)
    done = [n for n in names if (work / "out" / f"{n}.png").exists() and finish(work / "out" / f"{n}.png", ui / f"{n}.jpg")]
    print(f"{len(done)} of {len(names)} pictures in {time.time() - t0:.0f}s: {done}")
    if len(done) < len(names):
        print((r.stdout + r.stderr)[-600:])
    return len(done) == len(names)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pack", help="the pack source folder (packs/gvg)")
    ap.add_argument("--theme", required=True, help="the set's theme in a few sentences (places, colours, mood)")
    ap.add_argument("--only", nargs="*", choices=list(PICTURES))
    ap.add_argument("--no-guard", action="store_true")
    a = ap.parse_args()
    ui = Path(a.pack).resolve() / "ui"
    ui.mkdir(exist_ok=True)
    names = [n for n in (a.only or PICTURES) if not (ui / f"{n}.jpg").exists()]
    if not names:
        print("every picture is there")
        return 0
    guard = None if a.no_guard else subprocess.Popen([str(ROOT / "tools/codex_guard.sh"), "90", "pack_backgrounds.py"])
    try:
        return 0 if paint(ui, a.theme, names) else 1
    finally:
        if guard:
            guard.terminate()


if __name__ == "__main__":
    sys.exit(main())
