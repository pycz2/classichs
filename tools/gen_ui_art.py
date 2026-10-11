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
    "poison": (96, "a simple small round glass potion bottle with a cork, filled with bright toxic green poison, flat clean shapes, minimal detail"),
    "trigger": (96, "a small icon of a bright golden-yellow lightning bolt with a soft warm glow and a dark outline"),
    "mana": (128, "a simple blue hexagonal gem badge for a mana cost: a bevelled rim with a few facets only near the edge, and a large smooth, plain, evenly coloured centre with no detail, room for a big number"),
    "health": (128, "a simple red gem badge in the shape of a drop of blood, point upward: a bevelled rim and a large smooth, plain, evenly coloured centre with no facets or detail, room for a big number"),
    "attack_gem": (128, "a simple round golden-yellow gem badge: a thin dark gold bevelled rim and a large smooth, plain, evenly coloured centre with no facets or detail, room for a big number"),
    "sword": (96, "a short, simple, stylized sword icon standing upright, blade pointing up: a short broad plain steel blade, a wide gold cross guard, a clearly visible brown leather grip and a round gold pommel; the guard, grip and pommel take about 40% of the length; flat clean shapes, minimal detail"),
    "armor": (128, "a simple grey steel shield badge, a rounded heater shape: a bevelled rim and a large smooth, plain, evenly coloured centre with no rivets, scratches or detail, room for a big number"),
    "durability": (128, "a simple grey stone shield badge: a bevelled edge and a large smooth, plain, evenly coloured centre with no cracks or detail, room for a big number"),
    "class_DRUID": (128, "a simple flat round emblem: a plain brown disc with a thin gold rim and one bold, simple, flat light symbol of a bear paw print in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_HUNTER": (128, "a simple flat round emblem: a plain dark green disc with a thin gold rim and one bold, simple, flat light symbol of a bow with an arrow in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_MAGE": (128, "a simple flat round emblem: a plain blue disc with a thin gold rim and one bold, simple, flat light symbol of an eye in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_PALADIN": (128, "a simple flat round emblem: a plain gold disc with a thin gold rim and one bold, simple, flat light symbol of a war hammer in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_PRIEST": (128, "a simple flat round emblem: a plain white disc with a thin gold rim and one bold, simple, flat gold symbol of a pair of wings around a small sun in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_ROGUE": (128, "a simple flat round emblem: a plain dark grey disc with a thin gold rim and one bold, simple, flat light symbol of two crossed daggers in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_SHAMAN": (128, "a simple flat round emblem: a plain blue disc with a thin gold rim and one bold, simple, flat light symbol of a lightning bolt in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_WARLOCK": (128, "a simple flat round emblem: a plain purple disc with a thin gold rim and one bold, simple, flat light symbol of a horned demon skull in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_WARRIOR": (128, "a simple flat round emblem: a plain dark red disc with a thin gold rim and one bold, simple, flat light symbol of two crossed axes in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
    "class_NEUTRAL": (128, "a simple flat round emblem: a plain grey disc with a thin gold rim and one bold, simple, flat light symbol of a four-pointed star in the middle; no ornaments, no glow, no texture, minimal detail, like a clean game icon"),
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
