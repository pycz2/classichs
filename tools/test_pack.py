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
        "default_power": "P_A",
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

    def test_default_power_needed_with_champions(self):  # the engine refuses such a pack
        s = tiny()
        del s["rules.json"]["default_power"]
        self.assertTrue(any("default_power is missing" in e for e in errors(s)), errors(s))
        s["cards.json"] = [c for c in s["cards.json"] if c["type"] not in ("CHAMPION", "POWER")]
        self.assertFalse(any("default_power" in e for e in errors(s)))

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

    def test_ui_theme(self):
        s = tiny()
        s["ui/theme.json"] = {"colors": {"accent": "3ee8ff"}, "button": {"style": "neon"},
                              "fonts": {"body": "ui/fonts/Body.ttf"}}
        s["ui/fonts/Body.ttf"] = b"font"
        s["ui/fonts/OFL.txt"] = b"licence"
        self.assertEqual(errors(s), [])
        del s["ui/fonts/Body.ttf"]
        self.assertTrue(any("ui/fonts/Body.ttf is not in the pack" in e for e in errors(s)))
        s = tiny()
        s["ui/theme.json"] = {"button": {"style": "glass"}}
        self.assertTrue(errors(s))
        s = tiny()
        s["ui/theme.json"] = {"menu": {"crest": "ui/crest.png"}}
        self.assertTrue(any("ui/crest.png is not in the pack" in e for e in errors(s)))
        for p in ["ui/other.json", "ui/fonts/x.exe", "ui/fonts/a/b.ttf"]:
            s = tiny()
            s[p] = b"x"
            self.assertTrue(errors(s), p)

    def test_tutorial(self):
        def with_tutorial():
            s = tiny()
            s["manifest.json"]["locales"] = ["en", "ru"]
            s["missions/1.json"] = {"id": 1, "champion": "C_A", "boss": "C_A", "player": {"hand": ["M1"], "deck": []},
                                    "boss_deck": [], "reward": "M2", "hints": ["play"]}
            s["tutorial.json"] = {"unlock": "in_order", "effect": {"effect": "rain", "intensity": 0.5},
                                  "missions": [{"id": 1, "effect": "snow", "intro": [{"title": "a.title", "text": "a.text", "items": [
                                      {"card": "M1", "at": [100, 100], "scale": 2},
                                      {"note": "a.cost", "box": [0, 0, 100, 50], "to": {"card": 0, "part": "cost"}},
                                      {"hero": "C_A", "at": [600, 300], "health": 30},
                                      {"picture": "ui/hogger.png", "at": [0, 0], "size": [100, 100]}]}]}],
                                  "hints": {"play": [{"if": "can_play"}, {"if": "in_hand", "cards": ["M1"], "keyword": "WALL"}]}}
            s["ui/hogger.png"] = b"png"
            texts = {"tutorial": {"a.title": "A", "a.text": "B", "a.cost": "C"}, "hints": {"play": "Play!"},
                     "missions": {"1": {"intro": "Go", "lines": {"start": "Hi", "hurt": "Ow", "defeat": "Bye"}, "reward_line": "Yay"}}}
            s["locales/en.json"].update(json.loads(json.dumps(texts)))
            s["locales/ru.json"] = json.loads(json.dumps(texts))
            return s

        self.assertEqual(pack.check_files(as_files(with_tutorial())).errors, [])
        broken = [
            (lambda s: s["tutorial.json"].update({"stray": 1}), "unknown field 'stray'"),
            (lambda s: s["tutorial.json"]["missions"].append({"id": 2}), "missions/2.json is not in the pack"),
            (lambda s: s["tutorial.json"]["missions"].append({"id": 1}), "mission 1 twice"),
            (lambda s: s["tutorial.json"].update({"effect": "fog"}), "effect"),
            (lambda s: s["tutorial.json"]["missions"][0]["intro"][0]["items"].append({"card": "NOPE", "at": [0, 0]}), "unknown card NOPE"),
            (lambda s: s["tutorial.json"]["missions"][0]["intro"][0]["items"].append({"hero": "M1", "at": [0, 0]}), "not a CHAMPION"),
            (lambda s: s.pop("ui/hogger.png"), "picture ui/hogger.png is not in the pack"),
            (lambda s: s["tutorial.json"]["missions"][0]["intro"][0]["items"][1]["to"].update({"card": 1}), "points at card 1"),
            (lambda s: s["locales/en.json"]["tutorial"].pop("a.cost"), "no text tutorial.a.cost in locales/en.json"),
            (lambda s: s["locales/en.json"]["hints"].pop("play"), "no text hints.play in locales/en.json"),
            (lambda s: s["tutorial.json"]["hints"].pop("play"), "hint play has no rule"),
            (lambda s: s["tutorial.json"]["hints"]["play"].append({"if": "raining"}), "hints.play"),
        ]
        for spoil, want in broken:
            s = with_tutorial()
            spoil(s)
            errs = errors(s)
            self.assertTrue(any(want in e for e in errs), (want, errs))
        s = with_tutorial()
        del s["locales/ru.json"]["tutorial"]["a.title"]
        r = pack.check_files(as_files(s))
        self.assertEqual(r.errors, [])
        self.assertTrue(any("tutorial.a.title in locales/ru.json" in w for w in r.warnings), r.warnings)
        s = with_tutorial()
        del s["tutorial.json"]
        r = pack.check_files(as_files(s))
        self.assertTrue(any("without tutorial.json" in w for w in r.warnings), r.warnings)

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

    def test_local_sound_set_and_voice(self):
        with tempfile.TemporaryDirectory() as t:
            src = Path(t) / "src"
            for p, v in as_files(tiny()).items():
                (src / p).parent.mkdir(parents=True, exist_ok=True)
                (src / p).write_bytes(v)
            snd, vo = Path(t) / "snd", Path(t) / "vo"
            snd.mkdir()
            (snd / "M1_play.ogg").write_bytes(b"ogg")
            (snd / "notes.txt").write_bytes(b"skipped")
            (vo / "en").mkdir(parents=True)
            (vo / "en" / "M1_attack.ogg").write_bytes(b"ogg")
            files, r = pack.build(src, None, (), [f"original={snd}"], str(vo))
            self.assertEqual(r.errors, [])
            self.assertIn("sounds/original/M1_play.ogg", files)
            self.assertNotIn("sounds/original/notes.txt", files)
            self.assertIn("voice/en/M1_attack.ogg", files)
            self.assertIn("voice/LOCAL.md", files)
            self.assertEqual(json.loads(files["manifest.json"])["sound_sets"][-1], {"id": "original", "local": True})
            with self.assertRaises(pack.PackError):
                pack.build(src, None, (), (), str(Path(t) / "nothing"))
            # one set and the voice from several folders (the local packs of a chain: every level's sounds)
            snd2, vo2 = Path(t) / "snd2", Path(t) / "vo2"
            snd2.mkdir()
            (snd2 / "M2_play.mp3").write_bytes(b"mp3")
            (snd2 / "M1_play.ogg").write_bytes(b"later")
            (vo2 / "ru").mkdir(parents=True)
            (vo2 / "ru" / "M2_play.mp3").write_bytes(b"mp3")
            files, r = pack.build(src, None, (), [f"original={snd}", f"original={snd2}"], [str(vo), str(vo2)])
            self.assertEqual(r.errors, [])
            self.assertEqual(files["sounds/original/M1_play.ogg"], b"later")
            self.assertIn("sounds/original/M2_play.mp3", files)
            self.assertEqual([s["id"] for s in json.loads(files["manifest.json"])["sound_sets"]].count("original"), 1)
            self.assertIn("voice/en/M1_attack.ogg", files)
            self.assertIn("voice/ru/M2_play.mp3", files)

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


class Limits(unittest.TestCase):
    def test_the_same_everywhere(self):  # format.md "Size limits": 1 GiB a pack, 2 GiB unpacked, 50 000 files
        self.assertEqual((pack.LIMITS["pack"], pack.LIMITS["unpacked"], pack.LIMITS["files"]), (1 << 30, 2 << 30, 50000))
        gd = '{"pack": 1024 * MIB, "unpacked": 2048 * MIB, "files": 50000,'
        for f in ("game/pack.gd", "game/pack_check.gd"):
            self.assertIn(gd, (pack.REPO / f).read_text(), f)
        rs = (pack.REPO / "rust/engine/src/pack.rs").read_text()
        for line in ("MAX_PACK: usize = 1024 * MIB;", "MAX_UNPACKED: usize = 2048 * MIB;", "MAX_FILES: usize = 50_000;"):
            self.assertIn(line, rs)
        server = (pack.REPO / "server/src/packs.rs").read_text()
        for line in ("MAX_PLAYER_PACK: u64 = 1 << 30;", "MAX_SERVER_PACK: u64 = 1 << 30;"):
            self.assertIn(line, server)
        doc = (pack.REPO / "docs/packs/format.md").read_text()
        for row in ("| The `.cardpack` file | 1 GiB |", "| All files unpacked | 2 GiB |", "| Number of files | 50 000 |"):
            self.assertIn(row, doc)


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
        # the cards as in June 2014: the patch's null takes the later Mech tribe away, the source
        # locales give the 2014 names (Succubus, later Felstalker)
        by_id = {c["id"]: c for c in cards}
        self.assertNotIn("race", by_id["VAN_EX1_556"])
        self.assertEqual(by_id["VAN_EX1_560"]["turn_seconds"], 15)
        self.assertEqual(en["cards"]["VAN_EX1_306"]["name"], "Succubus")
        self.assertEqual(json.loads(files["locales/ru.json"])["cards"]["VAN_EX1_306"]["name"], "Суккуб")


class Chain(unittest.TestCase):
    """Packs built on packs (recipe `base`), as classic -> naxx -> gvg -> … (docs/packs/format.md §10)."""

    def write(self, root, path, v):
        p = root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(v if isinstance(v, bytes) else json.dumps(v).encode())

    def hs(self, cid, typ, cls, **kw):
        return {"id": cid, "type": typ, "cardClass": cls, "name": {"enUS": cid.lower()}, **kw}

    def three(self, t):
        """Packs a (root), b (on a), c (on b), each with its own card data, patch, scripts and texts."""
        t = Path(t)
        spec = tiny()
        self.write(t, "data/a.json", [self.hs("C_A", "HERO", "RED", health=30), self.hs("P_A", "HERO_POWER", "RED", cost=2),
                                      self.hs("COIN", "SPELL", "GREY", cost=0),
                                      self.hs("M1", "MINION", "GREY", rarity="C", set="CORE", collectible=True, cost=1,
                                              attack=1, health=2, mechanics=["WALL"])])
        self.write(t, "data/b.json", [self.hs("M2", "MINION", "RED", rarity="L", set="CORE", collectible=True, cost=5,
                                              attack=5, health=5)])
        self.write(t, "data/c.json", [self.hs("M3", "MINION", "GREY", rarity="C", set="CORE", collectible=True, cost=3,
                                              attack=3, health=3)])
        self.write(t, "data/c_texts.json", {"M1": {"name": {"enUS": "Wall of C"}}})
        self.write(t, "art/pics/M1.png", b"png")
        hsjson = {"do": "hsjson", "locales": {"en": "enUS"}, "rename": {"HERO": "CHAMPION", "HERO_POWER": "POWER"}}
        for name in "abc":
            for p in ("manifest.json", "rules.json", "decks/red.json"):
                self.write(t / name, p, spec[p])
        self.write(t, "b/manifest.json", {**spec["manifest.json"], "art_sets": [{"id": "pics"}]})
        self.write(t, "a/cards.patch.json", {"C_A": {"power": "P_A"}, "M1": {"cost": 1, "fx": {"play": "battlecry"}}})
        self.write(t, "b/cards.patch.json", {"M1": {"cost": 2}})
        self.write(t, "c/cards.patch.json", {"M1": {"attack": 9}})
        self.write(t, "a/recipe.json", {"root": "..", "steps": [
            {**hsjson, "from": "data/a.json", "patch": "cards.patch.json"},
            {"do": "copy", "from": "art/pics", "to": "art/pics", "files": ["*.png"]}]})
        self.write(t, "b/recipe.json", {"base": "../a", "root": "..", "steps": [
            {"do": "hsjson", "from": ["data/b.json"], "patch": ["cards.patch.json"]}]})
        self.write(t, "c/recipe.json", {"base": "../b", "root": "..", "skip": ["art/*"], "bundle_in_client": False,
                                        "steps": [{"do": "hsjson", "from": ["data/c.json"], "patch": ["cards.patch.json"],
                                                   "texts": ["data/c_texts.json"]}]})
        self.write(t, "a/scripts/a.lua", b"return {}\n")
        self.write(t, "a/scripts/x.lua", b"-- a\nreturn {}\n")
        self.write(t, "b/scripts/x.lua", b"-- b\nreturn {}\n")
        self.write(t, "a/ui/fonts/F.ttf", b"font")
        self.write(t, "a/locales/en.json", {"classes": {"RED": "Red of A", "GREY": "Grey of A"}, "decks": {"red": "A's deck"},
                                            "mechanics": {"WALL": {"name": "Wall", "tip": "Attack it first."}}})
        self.write(t, "b/locales/en.json", {"classes": {"RED": "Red of B"}, "sets": {"CORE": "Core of B"}})
        self.write(t, "c/locales/en.json", {"sets": {"CORE": "Core of C"}})
        return t

    def test_three_levels(self):
        with tempfile.TemporaryDirectory() as t:
            t = self.three(t)
            files, r = pack.build(t / "c")
            self.assertEqual(r.errors, [])
            cards = {c["id"]: c for c in json.loads(files["cards.json"])}
            self.assertEqual(sorted(cards), ["COIN", "C_A", "M1", "M2", "M3", "P_A"])  # every pack's data
            self.assertEqual((cards["M1"]["cost"], cards["M1"]["attack"]), (2, 9))  # patches in order, a later one wins
            self.assertEqual(cards["M1"]["fx"], {"play": "battlecry"})  # ... only for the fields it names
            self.assertEqual(files["scripts/x.lua"], b"-- b\nreturn {}\n")  # the nearer pack's script wins
            self.assertIn("scripts/a.lua", files)
            self.assertIn("ui/fonts/F.ttf", files)
            self.assertFalse([p for p in files if p.startswith("art/")])  # skip leaves the base's copy step out
            en = json.loads(files["locales/en.json"])
            self.assertEqual(en["classes"], {"RED": "Red of B", "GREY": "Grey of A"})
            self.assertEqual(en["sets"], {"CORE": "Core of C"})  # its own texts first
            self.assertNotIn("decks", en)  # only the shared sections
            self.assertEqual(en["cards"]["M1"]["name"], "Wall of C")  # its release-time texts
            self.assertFalse([p for p in files if "recipe" in p or "patch" in p or "texts" in p])
            files_b, r = pack.build(t / "b")  # the middle one keeps its art
            self.assertEqual(r.errors, [])
            self.assertIn("art/pics/M1.png", files_b)
            self.assertEqual(json.loads(files_b["cards.json"])[2]["cost"], 2)
            self.assertFalse(pack.bundle_in_client(t / "c"))
            self.assertTrue(pack.bundle_in_client(t / "b"))

    def test_up_to_date_sees_the_whole_chain(self):  # build --if-changed (tools/build_packs.sh)
        import os
        with tempfile.TemporaryDirectory() as t:
            t = self.three(t)
            out = t / "c.cardpack"
            self.assertFalse(pack.up_to_date(t / "c", out))  # not built yet
            out.write_bytes(b"x")
            old = out.stat().st_mtime - 100
            for f in t.rglob("*"):
                if f != out:
                    os.utime(f, (old, old))
            self.assertTrue(pack.up_to_date(t / "c", out))
            for src, changed in (("c", "a/scripts/a.lua"), ("c", "data/a.json"), ("c", "data/c_texts.json"), ("c", "a"),
                                 ("b", "art/pics/M1.png")):
                # the base's base, a data file, a texts file, a file gone (its folder), a folder a step copies
                os.utime(t / changed)
                self.assertFalse(pack.up_to_date(t / src, out), changed)
                os.utime(t / changed, (old, old))
            self.assertTrue(pack.up_to_date(t / "c", out))
            os.utime(t / "art/pics/M1.png")
            self.assertTrue(pack.up_to_date(t / "c", out))  # (c leaves out the base's art: skip)

    def test_bases_in_a_circle_are_refused(self):
        with tempfile.TemporaryDirectory() as t:
            t = self.three(t)
            self.write(t, "a/recipe.json", {"base": "../c", "root": "..", "steps": []})
            with self.assertRaises(pack.PackError):
                pack.build(t / "c")

    def test_naxxramas_is_built_on_classic(self):
        steps, bases = pack.recipe_steps(pack.REPO / "packs/naxx")
        self.assertEqual(bases, [(pack.REPO / "packs/classic").resolve()])
        hs = [s for _, s in steps if s["do"] == "hsjson"]
        self.assertEqual(len(hs), 1)
        self.assertEqual([Path(f).name for f in hs[0]["patch"]], ["cards.patch.json", "cards.patch.json"])
        self.assertEqual([Path(f).parent.name for f in hs[0]["patch"]], ["classic", "naxx"])
        self.assertFalse([s for _, s in steps if s.get("to") == "layout"])
        files, r = pack.build(pack.REPO / "packs/naxx")
        self.assertEqual(r.errors, [])
        self.assertIn("scripts/naxx.lua", files)
        self.assertIn("scripts/rogue.lua", files)
        self.assertEqual(len(json.loads(files["cards.json"])), 569)
        self.assertEqual(json.loads(files["manifest.json"])["rules_hash"],
                         "e47ac05550ae07647fcb8726d04b5a6cdbb28501c37420723e14c5cb690a90e7")


    def test_goblins_vs_gnomes_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/gvg")
        self.assertEqual((r.errors, r.warnings), ([], []))  # its new cards are drawn: no picture warning for them
        self.assertIn("art/simple/FP1_001.webp", files)  # Naxxramas's own pictures come along
        self.assertIn("art/simple/VAN_CS2_029.webp", files)  # Classic's by its recipe
        self.assertFalse([p for p in files if p.startswith("art/") and "/GVG_" in p])
        for s in ("basic", "classic", "naxx", "gvg"):
            self.assertIn(f"ui/set_{s}.png", files)
        self.assertIn("scripts/gvg.lua", files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/gvg"))


class ExtractSets(unittest.TestCase):
    def test_a_set_is_its_prefixed_cards_and_their_tokens(self):
        import extract_cards
        cards = [{"id": "GVG_001", "type": "SPELL", "set": "GVG", "collectible": True},
                 {"id": "GVG_110t", "type": "MINION", "set": "GVG"},
                 {"id": "PART_001", "type": "SPELL", "set": "GVG"},
                 {"id": "GVG_076_Puzzle", "type": "MINION", "set": "GVG"},
                 {"id": "GVG_010b", "type": "ENCHANTMENT", "set": "GVG"},
                 {"id": "GVG_999", "type": "MINION", "set": "HERO_SKINS"},
                 {"id": "GVG_043", "type": "WEAPON", "set": "GVG", "collectible": True, "health": 3},
                 {"id": "FP1_001", "type": "MINION", "set": "NAXX", "collectible": True}]
        got = extract_cards.set_cards(cards, "gvg")
        self.assertEqual([c["id"] for c in got], ["GVG_001", "GVG_043", "GVG_110t", "PART_001"])
        self.assertEqual(got[1]["durability"], 3)
        self.assertEqual([c["id"] for c in extract_cards.set_cards(cards, "naxx")], ["FP1_001"])


class Neonfall(unittest.TestCase):
    def test_neonfall_source_builds_clean_with_its_tutorial(self):
        files, r = pack.build(pack.REPO / "packs/neon")
        self.assertEqual(r.errors, [])
        self.assertEqual(r.warnings, [])
        t = json.loads(files["tutorial.json"])
        self.assertEqual([m["id"] for m in t["missions"]], [1, 2, 3, 4, 5, 6])
        self.assertEqual(len([p for p in files if p.startswith("missions/")]), 6)
        locs = {p: json.loads(b) for p, b in files.items() if p.startswith("locales/")}
        self.assertEqual(len(locs), 8)
        en = locs["locales/en.json"]
        for p, loc in locs.items():  # every language has every tutorial text of English
            for sec in ("tutorial", "hints", "missions"):
                self.assertEqual(set(loc[sec]), set(en[sec]), f"{p} {sec}")
            self.assertTrue(all(v.strip() for v in loc["tutorial"].values()), p)


if __name__ == "__main__":
    unittest.main()
