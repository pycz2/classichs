"""Tests of tools/apply_framing.py: python3 -m unittest tools/test_apply_framing.py (from the repo root)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply_framing  # noqa: E402


class Split(unittest.TestCase):
    def test_each_folder_gets_the_cards_it_has_pictures_of(self):
        with tempfile.TemporaryDirectory() as t:
            repo, local = Path(t) / "repo", Path(t) / "local"

            def put(path, data=b"pic"):
                p = Path(t) / path
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(data if isinstance(data, bytes) else json.dumps(data).encode())
            put("repo/packs/classic/recipe.json", {"root": "../..", "steps": [
                {"do": "copy", "from": "art/cards", "to": "art/generated", "files": ["*.jpg"]},
                {"do": "copy", "from": "art/simple", "to": "art/simple", "files": ["*.webp"]}]})
            put("repo/packs/classic/manifest.json", {"art_sets": [{"id": "generated"}, {"id": "simple"}]})
            put("repo/packs/naxx/manifest.json", {"art_sets": [{"id": "simple"}, {"id": "generated"}]})
            put("repo/art/cards/A.jpg")
            put("repo/art/simple/A.webp")
            put("repo/packs/naxx/art/simple/N.webp")
            put("repo/packs/naxx/art/simple/framing.json", {"OLD": {"x": 1}})
            put("repo/art/custom/A.jpg")  # the player's own folder
            put("repo/art/original/A.jpg")
            put("repo/art/original/framing.json", {"A": {"x": 1}})  # no longer moved: removed
            put("local/classic/art/A.webp")
            put("local/naxx/art/N.webp")
            put("local/naxx/set/N_play.opus")
            put("local/art-framing/index.html")  # not a pack's
            export = {"format": "classichs-art-framing/1", "sets": {
                "generated": {"A": {"x": 0.1, "y": -0.05, "zoom": 1.35}},
                "simple": {"A": {"zoom": 2}, "N": {"y": 0.2}, "Z": {"x": 0.5}},
                "custom": {"A": {"x": -0.2}, "N": {"x": 0, "y": 0, "zoom": 1}},
                "original": {"A": {"x": 0, "y": 0, "zoom": 1}}}}
            done, lost = apply_framing.apply(export, repo, local)

            def got(path):
                p = Path(t) / path / "framing.json"
                return json.loads(p.read_text()) if p.exists() else None
            self.assertEqual(got("repo/art/cards"), {"A": {"x": 0.1, "y": -0.05, "zoom": 1.35}})
            self.assertEqual(got("repo/art/simple"), {"A": {"zoom": 2}})
            self.assertEqual(got("repo/packs/naxx/art/simple"), {"N": {"y": 0.2}})  # replaced
            self.assertEqual(got("repo/art/custom"), {"A": {"x": -0.2}})
            self.assertEqual(got("local/classic/art"), {"A": {"x": -0.2}})
            self.assertIsNone(got("local/naxx/art"))  # N's custom picture is not moved
            self.assertIsNone(got("repo/art/original"))
            self.assertEqual(lost, [("simple", "Z")])
            self.assertEqual(len(done), 6)
            with self.assertRaises(SystemExit):
                apply_framing.apply({"format": "classichs-art-framing/1", "sets": {"simple": {"A": {"zoom": 9}}}}, repo, local)


if __name__ == "__main__":
    unittest.main()
