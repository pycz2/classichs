#!/usr/bin/env python3
"""Puts the owner's framing of the card pictures into the folders the packs' art sets are built from.

Usage: python3 tools/apply_framing.py art-framing.json [--local ~/ClassicHS-local]

art-framing.json is the export of ~/ClassicHS-local/art-framing/index.html (its make.py):
  {"format": "classichs-art-framing/1", "sets": {"<art set>": {"<card id>": {"x": …, "y": …, "zoom": …}}}}
Each folder of a set gets art/<set>/framing.json (docs/packs/format.md §7) with the cards it has a picture of:
  the copy steps of the packs' recipes (art/cards -> generated, art/simple -> simple, …), the packs' own folders
  (packs/<pack>/art/<set>/), the player's folders in art/ (custom, original: local, not in git) and every level's
  ~/ClassicHS-local/<pack>/art (the set `custom` of the local <pack>-custom-art.cardpack, tools/fetch_set_assets.py
  --build). tools/pack.py takes framing.json along with the pictures. The export holds every moved picture, so a
  folder's framing.json is replaced (and removed when none of its pictures is moved).
Then: tools/build_packs.sh for the public packs, tools/fetch_set_assets.py --set <pack> --build for the local ones.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pack  # noqa: E402

FORMAT = "classichs-art-framing/1"


def load(p):
    return json.loads(Path(p).read_text("utf-8"))


def folders(repo, local):
    """(set id, folder) of every folder an art set is built from."""
    out, sources = [], set()
    for f in sorted(repo.glob("packs/*/recipe.json")):
        for s in load(f).get("steps", []):
            if s.get("do") == "copy" and s["to"].startswith("art/"):
                d = (f.parent / load(f).get("root", ".") / s["from"]).resolve()
                sources.add(d)
                out.append((s["to"][4:], d))
    for m in sorted(repo.glob("packs/*/manifest.json")):
        out += [(s["id"], m.parent / "art" / s["id"]) for s in load(m).get("art_sets", [])
                if (m.parent / "art" / s["id"]).is_dir()]
    for d in sorted((repo / "art").iterdir()) if (repo / "art").is_dir() else []:
        if d.is_dir() and d.name != "cards" and d.resolve() not in sources:  # the player's own folders (ui/art.gd sets())
            out.append((d.name, d))
    for d in sorted(local.iterdir()) if local.is_dir() else []:
        if (d / "art").is_dir() and (repo / "packs" / d.name).is_dir():
            out.append(("custom", d / "art"))
    return list(dict.fromkeys(out))


def apply(export, repo=pack.REPO, local=Path.home() / "ClassicHS-local"):
    """Writes the framing.json files; returns ([(folder, cards)], [(set, card) placed nowhere])."""
    if export.get("format") != FORMAT:
        raise SystemExit(f"not a {FORMAT} file")
    sets = export.get("sets", {})
    for sid, cards in sets.items():
        errs = pack.validate(cards, pack.schema("framing.schema.json"))
        if errs:
            raise SystemExit(f"set {sid}: {errs[:5]}")
    still = {"x": 0, "y": 0, "zoom": 1}
    moved = {(sid, cid) for sid, cards in sets.items() for cid, v in cards.items() if {**still, **v} != still}
    done, placed = [], set()
    for sid, folder in folders(repo, local):
        pictures = {f.stem for f in folder.iterdir() if f.suffix.lower() in pack.IMAGES}
        mine = {cid: sets[sid][cid] for s, cid in sorted(moved) if s == sid and cid in pictures}
        placed |= {(sid, cid) for cid in mine}
        f = folder / "framing.json"
        if mine:
            f.write_bytes(pack.pretty(mine))
            done.append((folder, len(mine)))
        elif f.exists():
            f.unlink()
            done.append((folder, 0))
    return done, sorted(moved - placed)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("export")
    ap.add_argument("--local", default="~/ClassicHS-local")
    a = ap.parse_args()
    done, lost = apply(load(a.export), local=Path(a.local).expanduser())
    for folder, n in done:
        print(f"{n:5}  {folder}/framing.json")
    if lost:
        print(f"{len(lost)} moved pictures are in no folder of their set: {lost[:20]}")


if __name__ == "__main__":
    main()
