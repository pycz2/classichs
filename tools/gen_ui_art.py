#!/usr/bin/env python3
"""Generates the interface sprites (stat gems, keyword marks, the Taunt shield,
class emblems) with the local Codex CLI, on a green background that
tools/key_green.gd cuts out.

Usage: python3 tools/gen_ui_art.py [--only name ...] [--workers 3]
Result: ui/sprites/<name>.png. Existing files are kept (delete one to redo it).
"""
import argparse
import concurrent.futures as cf
import os
import subprocess

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "ui", "sprites")
WORK = os.path.join(ROOT, "build", "ui_art")
CODEX = os.environ.get("CODEX", "/Applications/ChatGPT.app/Contents/Resources/codex")

STYLE = (
    "A single game interface sprite for a warm, painterly fantasy collectible card game (tavern style): "
    "rich colours, soft highlights, a clean dark outline so it reads at a small size. "
    "Centred, front view, filling about 80% of a square 1:1 canvas. "
    "The background must be one flat pure chroma green (#00FF00) with no shadow, gradient or texture, "
    "and the object itself must contain no green at all. No text, letters, numbers or logos."
)

# name: (width in px after cutting out, what to draw)
SPRITES = {
    "taunt_shield": (220, "a sturdy heater shield seen straight from the front: grey stone and iron, a thick riveted metal rim, "
                          "a flat top edge and a pointed bottom, symmetrical, worn but solid, plain centre"),
    "deathrattle": (96, "a small icon of a white skull above two crossed bones, slightly stylized, bold dark outline"),
    "poison": (96, "a small round glass potion bottle with a cork, filled with bubbling bright purple poison, a tiny white skull mark on the glass"),
    "trigger": (96, "a small icon of a bright golden-yellow lightning bolt with a soft warm glow and a dark outline"),
    "mana": (128, "a glossy blue faceted crystal gem in the shape of a hexagon, light catching its facets, for a mana cost badge"),
    "health": (128, "a glossy red faceted gem in the shape of a drop of blood, point upward, light catching its facets"),
    "attack_gem": (128, "a glossy round golden-yellow faceted gem with a thin dark gold rim"),
    "sword": (160, "a short straight sword standing upright, blade pointing up: steel blade, gold cross guard, leather grip, round gold pommel"),
    "armor": (128, "a glossy grey steel shield badge, a rounded heater shape with a bevelled rim, for an armor value"),
    "durability": (128, "a grey stone shield badge with a bevelled edge and a few chips, for a weapon's durability value"),
    "class_DRUID": (128, "a round bronze medallion emblem with a brown bear paw print and two leaves, for the druid class"),
    "class_HUNTER": (128, "a round bronze medallion emblem with a drawn bow and an arrow, for the hunter class"),
    "class_MAGE": (128, "a round bronze medallion emblem with a glowing arcane eye inside a blue rune circle, for the mage class"),
    "class_PALADIN": (128, "a round bronze medallion emblem with a golden war hammer and rays of light, for the paladin class"),
    "class_PRIEST": (128, "a round bronze medallion emblem with a white winged sun circle, for the priest class"),
    "class_ROGUE": (128, "a round bronze medallion emblem with two crossed daggers, for the rogue class"),
    "class_SHAMAN": (128, "a round bronze medallion emblem with a carved totem and a lightning bolt, for the shaman class"),
    "class_WARLOCK": (128, "a round bronze medallion emblem with a purple horned demon skull and violet flames, for the warlock class"),
    "class_WARRIOR": (128, "a round bronze medallion emblem with two crossed battle axes over a red shield, for the warrior class"),
    "class_NEUTRAL": (128, "a round bronze medallion emblem with a simple grey four-pointed star, for neutral cards"),
    # full pictures (no green background, nothing cut out)
    "fatigue": (256, "FULL: a painterly fantasy card illustration of exhaustion: an empty, dusty deck box in a dark crypt, "
                     "a ghostly skeletal hand reaching out of purple mist, cold violet light. Square 1:1, no text."),
    "ice": (256, "FULL: a seamless square texture of thick frost and ice crystals on glass, white and pale blue, "
                 "feathery frost patterns and small cracks, evenly spread over the whole square, no object, no text."),
}
## Pictures that keep their background: resized, not cut out.
FULL = {n for n, v in SPRITES.items() if v[1].startswith("FULL: ")}


def run_batch(names):
    os.makedirs(os.path.join(WORK, "out"), exist_ok=True)
    lines = "\n".join(f"- {n}: {SPRITES[n][1].removeprefix('FULL: ')}" for n in names)
    style = "" if all(n in FULL for n in names) else STYLE
    prompt = (
        f"Use your built-in image generation tool (not code, not other tools) to create {len(names)} images, one per item "
        f"below, in the given order.\n{style}\n"
        "After generating each image, copy the generated PNG file to ./out/<name>.png (use the exact name). "
        "Do not create any other files. Items:\n" + lines
    )
    subprocess.run([CODEX, "exec", "--skip-git-repo-check", "--ephemeral", "-s", "workspace-write", "-C", WORK, prompt],
                   stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=1800)
    done = []
    for n in names:
        src = os.path.join(WORK, "out", n + ".png")
        if os.path.exists(src):
            dst = os.path.join(OUT, n + ".png")
            if n in FULL:
                subprocess.run(["sips", "-Z", str(SPRITES[n][0]), src, "--out", dst], capture_output=True)
            else:
                subprocess.run(["godot", "--headless", "--path", ROOT, "--script", "res://tools/key_green.gd", "--",
                                src, dst, str(SPRITES[n][0])], capture_output=True)
            if os.path.exists(dst):
                done.append(n)
    return done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--batch", type=int, default=4)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    todo = [n for n in (a.only or SPRITES) if not os.path.exists(os.path.join(OUT, n + ".png"))]
    batches = [todo[i:i + a.batch] for i in range(0, len(todo), a.batch)]
    print(f"{len(todo)} sprites in {len(batches)} batches", flush=True)
    with cf.ThreadPoolExecutor(a.workers) as ex:
        for done in ex.map(run_batch, batches):
            print("done:", done, flush=True)


if __name__ == "__main__":
    main()
