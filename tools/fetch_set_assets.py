#!/usr/bin/env python3
"""A set's Blizzard art and sounds for the owner's LOCAL packs, and those packs (never for git, never for a
distributed pack: they belong to Blizzard Entertainment).

Usage: python3 tools/fetch_set_assets.py --set gvg [--out ~/ClassicHS-local] [--only art|sounds|music] [--no-ru]
       python3 tools/fetch_set_assets.py --set gvg --build      the local pack ~/ClassicHS-local/<set>-custom-art.cardpack

Sets: classic, naxx and the later ones of tools/extract_cards.py SETS (gvg, brm, tgt, loe, og, kara, msg, ungoro,
icc, loot, gil). Result in <out>/<set>/:
  art/<card id>.webp     256x256 like art/custom, WebP: the set's cards and tokens from HearthstoneJSON
                         (art.hearthstonejson.com/v1/256x/<id>.jpg); classic: art/custom converted, naxx:
                         ~/ClassicHS-local/art-naxx converted (tools/fetch_2014_art.py made both)
  set/<name>.opus        card sounds and a legendary's play music (<card id>_music), Ogg Opus (tools/audio_codec.py)
  voice/<lang>/…         English and Russian lines, heroes' too (tools/fetch_original_sounds.py does the work)
  music/<slot>.opus      the original music: menu, mulligan, battle_1 … N, victory, defeat, arena
                         (tools/fetch_original_music.py does the work; its notes: <out>/audio-src/music/SOURCES.md)
  SOURCES.md
Downloads stay in <out>/sounds/cache (shared with tools/fetch_original_sounds.py) and <out>/sounds/cache/art.

--build makes <out>/<set>-custom-art.cardpack from packs/<set> (tools/pack.py build) with the art set `custom`,
the sound set `original` and the voice of every pack it is built on and its own (classic, naxx, …, <set>), and the
music set `original` of the nearest level that has one (a whole playlist, never merged): a pack
stands alone, it never takes pictures or sounds from another installed pack. An existing file is kept as
<set>-custom-art.before-<date>.cardpack. Needs ImageMagick (`magick`) and ffmpeg.
"""
import argparse
import concurrent.futures as cf
import datetime
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_cards  # noqa: E402
import fetch_card_sounds  # noqa: E402
import fetch_original_music  # noqa: E402
import fetch_original_sounds as snd  # noqa: E402
import pack  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
HSJSON_ART = "https://art.hearthstonejson.com/v1/256x/%s.jpg"


def webp(src, dst, trim=False):
    """A picture as the custom art is: a 256x256 square (centre crop), WebP. trim: first cut away white bars
    (HearthstoneJSON pads some later artworks, Dr. Boom's, with white at the sides)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    cut = ["-bordercolor", "white", "-border", "1", "-fuzz", "6%", "-trim", "+repage"] if trim else []
    r = subprocess.run(["magick", str(src)] + cut + ["-resize", "256x256^", "-gravity", "center", "-extent", "256x256",
                        "-strip", "-quality", "82", str(dst)], capture_output=True)
    return r.returncode == 0


def art(name, out, custom):
    dest = out / name / "art"
    if name in ("classic", "naxx"):  # the pictures tools/fetch_2014_art.py put there
        src = custom if name == "classic" else out / "art-naxx"
        files = [f for f in sorted(src.iterdir()) if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")]
        ok = sum(webp(f, dest / (f.stem + ".webp")) for f in files if not (dest / (f.stem + ".webp")).exists())
        print(f"{name}: {ok} pictures converted from {src} into {dest}")
        return
    cache = out / "sounds/cache/art"
    cache.mkdir(parents=True, exist_ok=True)
    ids = [c["id"] for c in extract_cards.pack_cards(snd.hsjson(), name)]

    def one(cid):
        dst, raw = dest / f"{cid}.webp", cache / f"{cid}.jpg"
        if dst.exists():
            return True
        if not raw.exists():
            try:
                raw.write_bytes(snd.get(HSJSON_ART % cid))
            except Exception:
                return False
        return webp(raw, dst, trim=True)
    with cf.ThreadPoolExecutor(6) as pool:
        got = list(pool.map(one, ids))
    missing = [i for i, ok in zip(ids, got) if not ok]
    print(f"{name}: {sum(got)} of {len(ids)} pictures in {dest}" + (f", none for {missing}" if missing else ""))


def sounds(name, out, ru):
    ru = snd.ru_for(name, out / "sounds/cache") if ru else {}
    snd.run(name, out, ru, cache=out / "sounds/cache", dest=out / name)
    fetch_card_sounds.run(name, out, ru)  # each card's other moments: aim, missile, impacts, trigger, …


def chain(name):
    """The packs a pack is built on and itself, the first first (classic, naxx, gvg, …)."""
    _, bases = pack.recipe_steps(ROOT / "packs" / name)
    return [b.name for b in reversed(bases)] + [name]


def build(name, out):
    dst = out / f"{name}-custom-art.cardpack"
    local = []
    for level in chain(name):  # every level's pictures, sounds and voice (a later level wins)
        if (out / level / "art").is_dir():
            local += ["--art-set", f"custom={out / level / 'art'}"]
        if (out / level / "set").is_dir():
            local += ["--sound-set", f"original={out / level / 'set'}"]
        if (out / level / "voice").is_dir():
            local += ["--voice", str(out / level / "voice")]
    music = [out / level / "music" for level in chain(name) if (out / level / "music").is_dir()]
    if music:  # the nearest level's: each folder is a set's whole playlist
        local += ["--music-set", f"original={music[-1]}"]
    before = dst.stat().st_size if dst.exists() else 0
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t) / dst.name
        if pack.main(["build", str(ROOT / "packs" / name), "-o", str(tmp)] + local) != 0:
            raise SystemExit(f"{name}: the build failed, {dst} is as it was")
        if dst.exists():
            keep = out / f"{name}-custom-art.before-{datetime.date.today():%Y%m%d}.cardpack"
            if not keep.exists():
                shutil.copy2(dst, keep)
            print(f"the old pack is kept as {keep}")
        shutil.move(str(tmp), dst)
    print(f"{dst}: {before / 2**20:.1f} MiB before, {dst.stat().st_size / 2**20:.1f} MiB now")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", required=True, choices=["classic"] + list(extract_cards.SETS))
    ap.add_argument("--out", default="~/ClassicHS-local")
    ap.add_argument("--only", choices=["art", "sounds", "music"])
    ap.add_argument("--no-ru", action="store_true", help="English voice only")
    ap.add_argument("--ffmpeg", default="/opt/homebrew/bin/ffmpeg" if Path("/opt/homebrew/bin/ffmpeg").exists() else "ffmpeg")
    ap.add_argument("--build", action="store_true", help="build the local pack from what is there (no downloads)")
    ap.add_argument("--custom", default=str(ROOT / "art/custom"), help="Classic's custom pictures (untracked, in the "
                    "owner's checkout)")
    a = ap.parse_args()
    out = Path(a.out).expanduser().resolve()
    if ROOT in out.parents or out == ROOT:
        raise SystemExit("--out must be outside the repository (these files never go into git)")
    if a.build:
        return build(a.set, out)
    snd.pick_encoder(a.ffmpeg)
    if a.only in (None, "art"):
        art(a.set, out, Path(a.custom).expanduser())
    if a.only in (None, "sounds"):
        sounds(a.set, out, not a.no_ru)
    if a.only in (None, "music"):
        fetch_original_music.run([a.set], out, a.ffmpeg)


if __name__ == "__main__":
    main()
