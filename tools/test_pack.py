"""Tests of tools/pack.py: python3 -m unittest tools/test_pack.py (from the repo root)."""
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pack  # noqa: E402


def tiny():
    """The smallest legal pack: two classes, a few cards, one deck."""
    cards = [
        {"id": "C_A", "type": "CHAMPION", "class": "RED", "health": 30, "power": "P_A"},
        {"id": "P_A", "type": "POWER", "class": "RED", "cost": 2},
        {"id": "COIN", "type": "SPELL", "class": "GREY", "cost": 0},
        {"id": "M1", "type": "MINION", "class": "GREY", "rarity": "C", "set": "CORE", "collectible": True,
         "cost": 1, "attack": 1, "health": 2, "keywords": ["WALL"], "fx": {"play": "battlecry"}},
        {"id": "M2", "type": "MINION", "class": "RED", "rarity": "L", "set": "CORE", "collectible": True,
         "cost": 5, "attack": 5, "health": 5},
    ]
    rules = {
        "format": 1,
        "limits": {"max_mana": 10, "hand": 10, "board": 7, "deck_size": 3, "copies": 2, "copies_by_rarity": {"L": 1}},
        "start": {"hand": [3, 4], "coin": "COIN"},
        "timers": {"turn": 75, "mulligan": 45},
        "classes": [{"id": "RED", "champion": "C_A"}, {"id": "GREY", "neutral": True}],
        "rarities": [{"id": "C", "tier": "common"}, {"id": "L", "tier": "legendary"}],
        "sets": ["CORE"],
        "mechanics": {"WALL": {"engine": "GUARD"}},
        "modes": {"constructed": {"sets": ["CORE"]}},
    }
    manifest = {"format": 1, "id": "test.tiny", "version": "1.0.0", "name": {"en": "Tiny"},
                "default_locale": "en", "locales": ["en"]}
    loc = {"cards": {c["id"]: {"name": c["id"].lower()} for c in cards},
           "mechanics": {"WALL": {"name": "Wall", "tip": "Attack it first."}}}
    deck = {"name": "Red", "champion": "C_A", "cards": ["M1", "M1", "M2"]}
    return {"manifest.json": manifest, "rules.json": rules, "cards.json": cards, "locales/en.json": loc,
            "decks/red.json": deck}


def as_files(spec):
    return {p: (v if isinstance(v, bytes) else json.dumps(v).encode()) for p, v in spec.items()}


def errors(spec):
    return pack.check_files(as_files(spec)).errors


class CanonicalJson(unittest.TestCase):
    def test_sorted_compact_utf8(self):
        self.assertEqual(pack.canonical({"b": 1, "a": ["é", "\n", True, None]}), '{"a":["é","\\n",true,null],"b":1}'.encode())

    def test_fractions_refused(self):
        with self.assertRaises(pack.PackError):
            pack.canonical({"a": 0.5})

    def test_duplicate_keys_and_bom_refused(self):
        with self.assertRaises(pack.PackError):
            pack.load_json(b'{"a": 1, "a": 2}')
        with self.assertRaises(pack.PackError):
            pack.load_json(b'\xef\xbb\xbf{}')
        with self.assertRaises(pack.PackError):
            pack.load_json(b'{"a": NaN}')


class Hashes(unittest.TestCase):
    def test_rules_hash_ignores_layout_and_looks(self):
        a = as_files(tiny())
        b = dict(a)
        b["rules.json"] = json.dumps(tiny()["rules.json"], indent=4, sort_keys=True).encode()  # same rules, other spacing
        cards = tiny()["cards.json"]
        cards[3]["fx"] = {"play": "portal"}  # a look only
        b["cards.json"] = json.dumps(cards).encode()
        b["locales/en.json"] = b"{}"
        self.assertEqual(pack.rules_hash(a), pack.rules_hash(b))
        self.assertNotEqual(pack.content_hash(a), pack.content_hash(b))

    def test_rules_hash_sees_rules(self):
        a = as_files(tiny())
        cards = tiny()["cards.json"]
        cards[3]["attack"] = 2
        b = dict(a, **{"cards.json": json.dumps(cards).encode()})
        self.assertNotEqual(pack.rules_hash(a), pack.rules_hash(b))
        c = dict(a, **{"scripts/x.lua": b"return {}\r\n"})
        d = dict(a, **{"scripts/x.lua": b"return {}\n"})
        self.assertNotEqual(pack.rules_hash(a), pack.rules_hash(c))
        self.assertEqual(pack.rules_hash(c), pack.rules_hash(d))  # line ends do not count

    def test_known_value(self):  # the formula of format.md, by hand
        import hashlib
        files = {"rules.json": b'{ "b": 1, "a": 2 }', "art/x/a.png": b"img"}
        line = "rules.json:" + hashlib.sha256(b'{"a":2,"b":1}').hexdigest() + "\n"
        self.assertEqual(pack.rules_hash(files), hashlib.sha256(("cardpack-rules/1\n" + line).encode()).hexdigest())


class Check(unittest.TestCase):
    def test_tiny_is_fine(self):
        r = pack.check_files(as_files(tiny()))
        self.assertEqual(r.errors, [])

    def test_bad_paths(self):
        for p in ["../evil.json", "/abs.json", "art/x/.hidden.png", "art/a.png", "foo/bar.json", "scripts/x.exe", "a\\b.json"]:
            s = tiny()
            s[p] = b"x"
            self.assertTrue(errors(s), p)

    def test_unknown_mechanic_and_engine_keyword(self):
        s = tiny()
        s["cards.json"][3]["keywords"] = ["NOPE"]
        self.assertTrue(any("NOPE" in e for e in errors(s)))
        s = tiny()
        s["rules.json"]["mechanics"]["WALL"]["engine"] = "TAUNT"
        self.assertTrue(any("not an engine keyword" in e for e in errors(s)))

    def test_missing_script_and_power(self):
        s = tiny()
        s["cards.json"][3]["script"] = "scripts/neutral.lua#M1"
        self.assertTrue(any("script" in e for e in errors(s)))
        s["scripts/neutral.lua"] = b"return {}"
        self.assertEqual(errors(s), [])
        s = tiny()
        s["cards.json"][0]["power"] = "M1"
        self.assertTrue(any("not a POWER" in e for e in errors(s)))

    def test_deck_rules(self):
        s = tiny()
        s["decks/red.json"]["cards"] = ["M1", "M2", "M2"]
        self.assertTrue(any("copies of M2" in e for e in errors(s)))
        s["decks/red.json"]["cards"] = ["M1", "M1"]
        self.assertTrue(any("exactly 3" in e for e in errors(s)))
        s["decks/red.json"]["cards"] = ["M1", "M1", "P_A"]
        self.assertTrue(any("can't be put" in e for e in errors(s)))

    def test_schema(self):
        s = tiny()
        s["rules.json"]["limits"]["hand"] = "ten"
        self.assertTrue(any("limits.hand" in e for e in errors(s)))
        s = tiny()
        s["cards.json"][3]["power_level"] = 9000
        self.assertTrue(any("unknown field" in e for e in errors(s)))

    def test_stale_rules_hash(self):
        s = tiny()
        s["manifest.json"]["rules_hash"] = "0" * 64
        self.assertTrue(any("rules_hash" in e for e in errors(s)))


class BuildAndZip(unittest.TestCase):
    def test_build_is_deterministic_and_checks(self):
        with tempfile.TemporaryDirectory() as t:
            src = Path(t) / "src"
            for p, v in as_files(tiny()).items():
                (src / p).parent.mkdir(parents=True, exist_ok=True)
                (src / p).write_bytes(v)
            (src / "recipe.json").write_text('{"steps": []}')
            out1, out2 = Path(t) / "a.cardpack", Path(t) / "b.cardpack"
            files, r = pack.build(src, out1)
            self.assertEqual(r.errors, [])
            pack.build(src, out2)
            self.assertEqual(out1.read_bytes(), out2.read_bytes())
            back = pack.read_pack(out1)
            self.assertEqual(back, files)
            self.assertNotIn("recipe.json", back)
            man = json.loads(back["manifest.json"])
            self.assertEqual(man["rules_hash"], pack.rules_hash(back))
            self.assertEqual(man["fx"], ["battlecry"])
            with zipfile.ZipFile(out1) as z:
                self.assertEqual([i.date_time for i in z.infolist()], [pack.ZIP_TIME] * len(back))

    def test_art_set_flag_never_takes_original(self):
        with tempfile.TemporaryDirectory() as t:
            src = Path(t) / "src"
            for p, v in as_files(tiny()).items():
                (src / p).parent.mkdir(parents=True, exist_ok=True)
                (src / p).write_bytes(v)
            with self.assertRaises(pack.PackError):
                pack.build(src, None, [f"orig={pack.REPO / 'art/original'}"])
            art = Path(t) / "mine"
            art.mkdir()
            (art / "M1.png").write_bytes(b"png")
            files, r = pack.build(src, None, [f"mine={art}"])
            self.assertIn("art/mine/M1.png", files)
            self.assertEqual(json.loads(files["manifest.json"])["art_sets"], [{"id": "mine", "local": True}])

    def test_read_pack_refuses_duplicates(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "x.cardpack"
            with zipfile.ZipFile(p, "w") as z:
                z.writestr("manifest.json", "{}")
                import warnings
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    z.writestr("manifest.json", "{}")
            with self.assertRaises(pack.PackError):
                pack.read_pack(p)


class Classic(unittest.TestCase):
    def test_classic_source_builds_clean(self):
        files, r = pack.build(pack.REPO / "packs/classic")
        self.assertEqual(r.errors, [])
        self.assertEqual(r.warnings, [])
        self.assertFalse([p for p in files if "original" in p or "custom" in p])
        cards = json.loads(files["cards.json"])
        self.assertEqual(len(cards), 534)
        self.assertEqual(len([p for p in files if p.startswith("locales/")]), 8)
        self.assertEqual(len([p for p in files if p.startswith("decks/")]), 10)
        rules = json.loads(files["rules.json"])
        self.assertEqual([x["rank"] for x in rules["ranked"]["ranks"]], list(range(25, 0, -1)))
        en = json.loads(files["locales/en.json"])
        self.assertEqual(en["ranks"]["25"], "Angry Chicken")
        self.assertEqual(en["mechanics"]["TAUNT"]["name"], "Taunt")


if __name__ == "__main__":
    unittest.main()
