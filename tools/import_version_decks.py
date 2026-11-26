#!/usr/bin/env python3
"""Copies the prepared HearthPwn decks of each game version into packs/eras (packs/eras/README.md, "Decks").

The decks were picked and checked locally (~/ClassicHS-local/prep/decks/README.md): <build>/<standard|wild>/*.json,
each in the pack's deck format with its HearthPwn name, author and link in the description. They go to
packs/eras/versions/<build>/decks/<format>_<file>.json, a deck once per version (a Standard deck is a Wild deck too:
its first, Standard file is kept). The builder (tools/pack.py) puts them into the version with its base pack's decks.

    python3 tools/import_version_decks.py [--src DIR] [build …]     (no build: every version of DIR)
"""
import argparse
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FORMATS = ("standard", "wild")


def import_version(src, out, build):
    """Writes version build's decks from src into out/<build>/decks/; returns how many per format."""
    folder = Path(out) / build / "decks"
    for f in folder.glob("*.json"):
        if f.name.startswith(tuple(f"{fmt}_" for fmt in FORMATS)):
            f.unlink()  # (what an earlier run wrote)
    seen, counts = set(), {}
    for fmt in FORMATS:
        counts[fmt] = 0
        for f in sorted((Path(src) / build / fmt).glob("*.json")):
            d = json.loads(f.read_bytes())
            key = (d["champion"], tuple(sorted(d["cards"])))
            if key in seen:
                continue
            seen.add(key)
            folder.mkdir(parents=True, exist_ok=True)
            (folder / f"{fmt}_{f.name}").write_bytes(f.read_bytes())
            counts[fmt] += 1
    return counts


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--src", default=Path.home() / "ClassicHS-local/prep/decks", type=Path)
    ap.add_argument("--out", default=REPO / "packs/eras/versions", type=Path)
    ap.add_argument("builds", nargs="*")
    a = ap.parse_args(argv)
    builds = a.builds or sorted((p.name for p in a.src.iterdir() if p.name.isdigit()), key=int)
    for b in builds:
        c = import_version(a.src, a.out, b)
        print(f"{b}: {c['standard']} Standard, {c['wild']} more from the Wild lists")


if __name__ == "__main__":
    main()
