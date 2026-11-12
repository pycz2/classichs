"""Tests of tools/fetch_original_music.py: python3 -m unittest tools/test_fetch_original_music.py (from the repo root)."""
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_original_music as fom  # noqa: E402


def _has_vorbis():
    try:
        fom._lib("vorbisenc")
        return True
    except SystemExit:
        return False


class Plan(unittest.TestCase):
    def test_every_pack_has_every_slot(self):
        for s in fom.SETS:
            p = fom.plan(s)
            for slot in ("menu", "mulligan", "victory", "defeat", "arena", "battle_1", "battle_3"):
                self.assertIn(slot, p, f"{s}: {slot}")

    def test_the_adventures_play_their_own_board_music(self):
        self.assertEqual(fom.plan("naxx")["menu"], "Naxx_Menu_Music")
        self.assertTrue(all(t.startswith("Naxx_") for k, t in fom.plan("naxx").items() if k.startswith("battle_")))
        self.assertEqual([fom.plan("gvg")[f"battle_{i}"] for i in range(1, 6)], fom.DEFAULT_POOL)
        self.assertNotIn("battle_4", fom.plan("brm"))


class Ogg(unittest.TestCase):
    @unittest.skipUnless(shutil.which("ffmpeg"), "needs ffmpeg")
    def test_a_page_is_written_as_ogg_writes_it(self):
        """The first page of a real Ogg file (ffmpeg's Opus) rebuilt from its packet: the same bytes (CRC, lacing)."""
        with tempfile.TemporaryDirectory() as t:
            f = Path(t) / "a.opus"
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=d=0.2", "-c:a", "libopus", str(f)],
                           check=True)
            d = f.read_bytes()
        flags, granule, serial, seq, nseg = d[5], *struct.unpack_from("<qII", d, 6), d[26]
        body = d[27 + nseg:27 + nseg + sum(d[27:27 + nseg])]
        self.assertEqual(fom.ogg_page([body], granule, seq, flags, serial), d[:27 + nseg + len(body)])

    @unittest.skipUnless(_has_vorbis(), "needs libvorbis")
    def test_the_modes_of_a_setup_header(self):
        (_ident, _comment, setup), (short, long_) = fom.vorbis_headers(81, 2, 48000)
        self.assertEqual(fom.mode_blockflags(setup), [0, 1], "libvorbisenc: a short and a long mode")
        self.assertLess(short, long_)
        self.assertIn(zlib.crc32(setup), fom.VORBIS_SETUP, "the header FMOD's quality 81 names")


if __name__ == "__main__":
    unittest.main()
