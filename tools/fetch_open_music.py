#!/usr/bin/env python3
"""Downloads the open music set (CC0 tracks by RandomMind from OpenGameArt) and
encodes it for the game: audio/open/<slot>.opus (tools/audio_codec.py, music), chosen in Settings → Music.
The originals (MP3) stay out of git, cached in ~/ClassicHS-local/audio-src/open/ (downloaded once).
The generated set is audio/<slot>.wav (tools/gen_audio.py).

Usage: python3 tools/fetch_open_music.py   (needs curl and ffmpeg with libopus)
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import audio_codec  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "audio", "open")
CACHE = os.path.expanduser("~/ClassicHS-local/audio-src/open")
FILES = "https://opengameart.org/sites/default/files/"
# slot: (title, page, file)
TRACKS = {
    "menu": ("Medieval: Minstrel Dance", "https://opengameart.org/content/medieval-minstrel-dance", "Minstrel_Dance_0.mp3"),
    "battle_1": ("Medieval: The Old Tower Inn", "https://opengameart.org/content/medieval-the-old-tower-inn", "The_Old_Tower_Inn.mp3"),
    "battle_2": ("Medieval: King's Feast", "https://opengameart.org/content/medieval-kings-feast", "Kings_Feast_0.mp3"),
    "battle_3": ("Medieval: The Bard's Tale", "https://opengameart.org/content/medieval-the-bards-tale", "The_Bards_Tale.mp3"),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)
    for slot, (_title, _page, file) in TRACKS.items():
        src = os.path.join(CACHE, file)
        if not os.path.exists(src):
            subprocess.run(["curl", "-sSL", "--retry", "3", "-o", src + ".part", FILES + file], check=True)
            os.replace(src + ".part", src)
            time.sleep(1)
        if not audio_codec.encode_opus(src, os.path.join(OUT, slot + ".opus"), "music"):
            raise SystemExit(f"ffmpeg could not encode {slot}.opus (it needs libopus)")
        print("wrote", slot)
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("# Open music set\n\nAll tracks by **RandomMind**, released under **CC0** (public domain) on OpenGameArt.\n\n")
        for slot, (title, page, _file) in TRACKS.items():
            f.write(f"- `{slot}.opus` — {title}: {page}\n")


if __name__ == "__main__":
    main()
