#!/usr/bin/env python3
"""Puts the June 2014 art back into the owner's local custom art set, and fetches the Naxxramas art.

Usage: python3 tools/fetch_2014_art.py [--custom art/custom] [--backup ~/ClassicHS-local/art-custom-backup]
                                       [--naxx ~/ClassicHS-local/art-naxx] [--only classic|naxx]

The art belongs to Blizzard Entertainment: art/custom is not in git, the Naxxramas folder is outside the
repository, and neither goes into a distributed pack (only into the owner's local packs, tools/pack.py
--art-set). This script holds only where the pictures come from.

Classic: the cards whose art Blizzard changed after June 2014. How they were found: the wiki's change
records (Cargo table CardChange, artist changes of every Classic card), the patch notes (Patch 14.6.0.31761
"Card Art Updates", July 2019: Succubus -> Felstalker, Windfury Harpy, Secretkeeper, Eviscerate, Bite,
Deadly Shot, Headcrack; Mistress of Pain is not Classic) and a picture comparison of every card against
its archived 2016 card render (web.archive.org copies of wow.zamimg.com/images/hearthstone/cards/enus/medium/).
The Druid Choose One option cards (EX1_154a, EX1_155a, …) got their own pictures in 2019; they keep them.
The 2014 pictures are the full artworks the wiki keeps (hearthstone.wiki.gg/images/<file>), cropped to a
square and scaled to 256x256 like the other custom pictures. The replaced files are copied to the backup
folder first (once). Needs ImageMagick (`magick`).

Naxxramas: the FP1_* cards' current art from HearthstoneJSON (art.hearthstonejson.com/v1/256x/<id>.jpg),
as art/custom was made; none of them changed since July 2014 (the same checks).
"""
import argparse
import json
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIKI = "https://hearthstone.wiki.gg/images/"
UA = "ClassicHSArtCollector/1.0 (hobby fan project)"  # wiki.gg rejects browser user agents
HSJSON_ART = "https://art.hearthstonejson.com/v1/256x/%s.jpg"
HSJSON = "https://api.hearthstonejson.com/v1/latest/enUS/cards.json"

# card id (as in art/custom) -> (the wiki's file of the 2014 artwork, square crop x, y, size in its pixels)
ART_2014 = {
    "VAN_EX1_306": ("Succubus_full.jpg", 0, 0, 640),               # Succubus (now Felstalker), Matt Dixon
    "VAN_EX1_033": ("Windfury_Harpy_full_old.jpg", 110, 0, 708),   # Windfury Harpy
    "VAN_EX1_080": ("Secretkeeper_full_old.jpeg", 0, 0, 1149),     # Secretkeeper
    "VAN_EX1_124": ("Eviscerate_full.jpg", 0, 0, 1024),            # Eviscerate: the 2014 art with its blood
    "VAN_EX1_570": ("Bite_full_old.jpg", 0, 40, 1044),             # Bite
    "VAN_EX1_617": ("Deadly_Shot_full_old.jpg", 96, 0, 832),       # Deadly Shot
    "VAN_EX1_137": ("Headcrack_full_old.jpg", 150, 0, 1063),       # Headcrack
}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=90).read()


def classic(custom, backup):
    backup.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for cid, (name, x, y, size) in sorted(ART_2014.items()):
            dst = custom / f"{cid}.jpg"
            if dst.exists() and not (backup / dst.name).exists():
                shutil.copy2(dst, backup / dst.name)
            src = Path(tmp) / name
            src.write_bytes(get(WIKI + urllib.parse.quote(name)))
            subprocess.run(["magick", str(src), "-crop", f"{size}x{size}+{x}+{y}", "+repage",
                            "-resize", "256x256!", "-strip", "-quality", "90", str(dst)], check=True)
            print(cid, "<-", name)


def naxx(folder):
    folder.mkdir(parents=True, exist_ok=True)
    ids = sorted(c["id"] for c in json.loads(get(HSJSON)) if c["id"].startswith("FP1_") and c.get("set") == "NAXX")
    n = 0
    for cid in ids:
        dst = folder / f"{cid}.jpg"
        if dst.exists():
            continue
        try:
            dst.write_bytes(get(HSJSON_ART % cid))
            n += 1
        except Exception as e:  # a card without art (an enchantment)
            print(cid, "no art:", e)
    print(f"Naxxramas: {len(ids)} cards, {n} pictures fetched into {folder}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--custom", default=str(ROOT / "art/custom"))
    ap.add_argument("--backup", default="~/ClassicHS-local/art-custom-backup")
    ap.add_argument("--naxx", default="~/ClassicHS-local/art-naxx")
    ap.add_argument("--only", choices=["classic", "naxx"])
    a = ap.parse_args()
    if a.only != "naxx":
        classic(Path(a.custom).expanduser(), Path(a.backup).expanduser())
    if a.only != "classic":
        naxx(Path(a.naxx).expanduser())


if __name__ == "__main__":
    main()
