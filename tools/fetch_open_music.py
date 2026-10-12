#!/usr/bin/env python3
"""Downloads the open music set (CC0 tracks by RandomMind from OpenGameArt) and
encodes it for the game: audio/open/<slot>.ogg, chosen in Settings → Music.
The generated set is audio/<slot>.wav (tools/gen_audio.py).

Usage: python3 tools/fetch_open_music.py   (needs curl and ffmpeg)
"""
import os
import subprocess
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "audio", "open")
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
    with tempfile.TemporaryDirectory() as tmp:
        for slot, (_title, _page, file) in TRACKS.items():
            src = os.path.join(tmp, file)
            subprocess.run(["curl", "-sSL", "-o", src, FILES + file], check=True)
            # Vorbis quality 1 (about 80 kbit/s): background music, a small download
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-vn", "-c:a", "libvorbis", "-q:a", "1",
                            os.path.join(OUT, slot + ".ogg")], check=True)
            print("wrote", slot)
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("# Open music set\n\nAll tracks by **RandomMind**, released under **CC0** (public domain) on OpenGameArt.\n\n")
        for slot, (title, page, _file) in TRACKS.items():
            f.write(f"- `{slot}.ogg` — {title}: {page}\n")


if __name__ == "__main__":
    main()
