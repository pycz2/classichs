#!/usr/bin/env python3
"""Tries new art styles on a few cards: each style draws the same cards with the
local Codex CLI (like tools/gen_card_art.py), into build/art_styles/<style>/<id>.jpg,
and tools/art_styles_page.py puts them side by side with the current art.

Usage: python3 tools/gen_art_styles.py [--styles cartoon simple photo] [--workers 3]
Existing pictures are kept (delete one to draw it again).
"""
import argparse
import concurrent.futures as cf
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_card_art import CODEX, describe  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "build", "art_styles")
SIZE = 512

## 15 different cards: heroes, minions of several kinds, spells, a weapon, a Secret.
CARDS = ["HERO_08", "HERO_01", "HERO_06", "VAN_CS2_182", "VAN_EX1_298", "VAN_EX1_116", "VAN_CS2_168",
         "VAN_EX1_412", "VAN_EX1_043", "VAN_CS2_029", "VAN_CS2_093", "VAN_EX1_339", "VAN_CS2_106",
         "VAN_EX1_289", "VAN_EX1_006"]

COMMON = (
    "Show only the essence of the card so it reads at a glance even very small: one clear subject, "
    "large in the frame, nothing that distracts. Square 1:1. Absolutely no text, letters, numbers, "
    "card frames, borders, UI, watermarks or logos. Invent an original composition: do not copy or "
    "imitate any existing card art, game screenshots or official character designs."
)
STYLES = {
    "cartoon": "Style: a flat 2D cartoon with the absolute minimum of detail — bold simple shapes, thick clean "
               "outlines, flat colours with at most one soft shade, a plain one- or two-colour background, no "
               "texture and no small details, like a clear modern game icon or a children's animated show. " + COMMON,
    "simple": "Style: a hand-painted collectible card game illustration with very few details — clean readable "
              "shapes, soft painterly shading, a limited warm palette, a simple uncluttered background (a soft "
              "gradient or a hint of the setting), no busy ornaments or clutter. " + COMMON,
    "photo": "Style: photorealistic, but with the minimum of detail — a single subject lit like a cinematic "
             "studio still, realistic materials, shallow depth of field, a clean dark or neutral background, "
             "simple composition, no clutter; fantasy creatures and magic rendered as if photographed. " + COMMON,
}


def run_batch(style, batch, cards):
    work = os.path.join(OUT, "_work", style)
    os.makedirs(os.path.join(work, "out"), exist_ok=True)
    lines = "\n".join(f"- ID {i}: {describe(cards[i])}" for i in batch)
    prompt = (
        f"Use your built-in image generation tool (not code, not other tools) to create {len(batch)} images, "
        "one per card listed below, in the given order. For each card, show what the card is: the creature "
        "or character, the weapon, or the visible magic of the spell.\n"
        f"{STYLES[style]}\n"
        "After generating each image, copy the generated PNG file to ./out/<ID>.png (use the exact ID). "
        "Do not create any other files. Cards:\n" + lines
    )
    subprocess.run([CODEX, "exec", "--skip-git-repo-check", "--ephemeral", "-s", "workspace-write", "-C", work, prompt],
                   stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=2400)
    done = []
    for i in batch:
        src = os.path.join(work, "out", i + ".png")
        if os.path.exists(src):
            dst = os.path.join(OUT, style, i + ".jpg")
            subprocess.run(["sips", "-Z", str(SIZE), "-s", "format", "jpeg", "-s", "formatOptions", "82", src, "--out", dst],
                           capture_output=True)
            if os.path.exists(dst):
                done.append(i)
    return style, done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--styles", nargs="+", default=list(STYLES))
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--batch", type=int, default=5)
    a = ap.parse_args()
    data = json.load(open(os.path.join(ROOT, "data", "cards.json")))
    cards = {c["id"]: c for c in (data if isinstance(data, list) else data.values())}
    jobs = []
    for style in a.styles:
        os.makedirs(os.path.join(OUT, style), exist_ok=True)
        todo = [i for i in CARDS if not os.path.exists(os.path.join(OUT, style, i + ".jpg"))]
        jobs += [(style, todo[k:k + a.batch]) for k in range(0, len(todo), a.batch)]
    print(f"{len(jobs)} batches", flush=True)
    with cf.ThreadPoolExecutor(a.workers) as ex:
        for style, done in ex.map(lambda j: run_batch(j[0], j[1], cards), jobs):
            print(style, "done:", done, flush=True)


if __name__ == "__main__":
    main()
