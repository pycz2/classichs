"""Tests of tools/pack.py: python3 -m unittest tools/test_pack.py (from the repo root)."""
import contextlib
import io
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

    def test_ui_tile(self):  # the library's tile picture: any shape is taken, one far from 5:2 is cut (a warning)
        with open(Path(__file__).resolve().parent.parent / "packs/loot/ui/tile.jpg", "rb") as f:
            jpg = f.read()
        self.assertEqual(pack.image_size(jpg), (750, 300))
        png = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + (400).to_bytes(4, "big") + (400).to_bytes(4, "big")
        self.assertEqual(pack.image_size(png), (400, 400))
        s = tiny()
        s["ui/tile.jpg"] = jpg
        self.assertEqual(pack.check_files(as_files(s)).warnings, [])
        s = tiny()
        s["ui/tile.png"] = png
        r = pack.check_files(as_files(s))
        self.assertEqual(r.errors, [])
        self.assertTrue(any("ui/tile.png: 400x400" in w for w in r.warnings), r.warnings)

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

    def test_opus_sounds_music_voice_and_local_music_set(self):
        with tempfile.TemporaryDirectory() as t:
            src = Path(t) / "src"
            s = tiny()
            s["manifest.json"]["sound_sets"] = [{"id": "default", "default": True}]
            for p, v in as_files(s).items():
                (src / p).parent.mkdir(parents=True, exist_ok=True)
                (src / p).write_bytes(v)
            (src / "sounds/default").mkdir(parents=True)
            (src / "sounds/default/attack.opus").write_bytes(b"OggS opus" * 50)
            mus, vo = Path(t) / "mus", Path(t) / "vo"
            mus.mkdir()
            (mus / "menu.opus").write_bytes(b"OggS opus" * 50)
            (mus / "battle_1.ogg").write_bytes(b"ogg")
            (mus / "notes.txt").write_bytes(b"skipped")
            (vo / "en").mkdir(parents=True)
            (vo / "en" / "M1_play.opus").write_bytes(b"OggS opus")
            out = Path(t) / "x.cardpack"
            files, r = pack.build(src, out, (), (), str(vo), [f"mine={mus}"])
            self.assertEqual(r.errors, [])
            self.assertIn("music/mine/menu.opus", files)
            self.assertIn("music/mine/battle_1.ogg", files)
            self.assertNotIn("music/mine/notes.txt", files)
            self.assertEqual(json.loads(files["manifest.json"])["music_sets"], [{"id": "mine", "local": True}])
            self.assertEqual(pack.check_files(pack.read_pack(out)).errors, [])
            with zipfile.ZipFile(out) as z:
                kinds = {i.filename: i.compress_type for i in z.infolist()}
            for p in ("sounds/default/attack.opus", "music/mine/menu.opus", "voice/en/M1_play.opus"):
                self.assertEqual(kinds[p], zipfile.ZIP_STORED, p)
            self.assertEqual(kinds["cards.json"], zipfile.ZIP_DEFLATED)
            with self.assertRaises(pack.PackError):
                pack.build(src, None, music_sets=[f"bad={Path(t) / 'nothing'}"])
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(pack.main(["build", str(src), "-o", str(out), "--music-set", f"mine={mus}"]), 0)
            self.assertIn("music/mine/menu.opus", pack.read_pack(out))

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


class Framing(unittest.TestCase):
    """art/<set>/framing.json: where each picture sits in its window (format.md §7)."""

    def test_checked_and_not_a_rules_file(self):
        s = tiny()
        s["manifest.json"]["art_sets"] = [{"id": "pics"}]
        s["art/pics/M1.png"] = b"png"
        s["art/pics/framing.json"] = {"M1": {"x": 0.1, "y": -0.05, "zoom": 1.35}}
        r = pack.check_files(as_files(s))
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertEqual(pack.rules_hash(as_files(s)), pack.rules_hash(as_files(tiny())))
        s["art/pics/framing.json"] = {"M1": {"zoom": 9}}
        self.assertTrue(any("framing.json" in e for e in errors(s)))
        s["art/pics/framing.json"] = {"M2": {"x": 0.1}}  # no picture of M2 in the set
        self.assertTrue(any("framing.json" in w for w in pack.check_files(as_files(s)).warnings))
        del s["art/pics/framing.json"]
        s["art/pics/other.json"] = {}
        self.assertTrue(any("framing.json" in e for e in errors(s)))

    def test_build_takes_it_from_copies_bases_and_local_sets(self):
        with tempfile.TemporaryDirectory() as t:
            t = Chain().three(t)  # a copies art/pics; b and c are built on it
            Chain().write(t, "art/pics/framing.json", {"M1": {"x": 0.5}})
            Chain().write(t, "b/art/pics/M2.png", b"png")
            Chain().write(t, "b/art/pics/framing.json", {"M2": {"zoom": 2}})
            files, r = pack.build(t / "b")
            self.assertEqual(r.errors, [])
            self.assertEqual(json.loads(files["art/pics/framing.json"]), {"M1": {"x": 0.5}, "M2": {"zoom": 2}})
            files, _ = pack.build(t / "c")  # c skips a's copies; b's own pictures come along with their framing
            self.assertEqual(json.loads(files["art/pics/framing.json"]), {"M2": {"zoom": 2}})
            for level, fr in (("one", {"M1": {"x": 0.1}, "M2": {"y": 0.2}}), ("two", {"M1": {"x": -0.3}})):
                Chain().write(t, f"{level}/M1.png", b"png")
                Chain().write(t, f"{level}/framing.json", fr)
            files, r = pack.build(t / "a", None, [f"mine={t / 'one'}", f"mine={t / 'two'}"])
            self.assertEqual(json.loads(files["art/mine/framing.json"]), {"M1": {"x": -0.3}, "M2": {"y": 0.2}})  # a later one wins


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
        self.assertEqual(json.loads(files["manifest.json"])["rules_hash"],
                         "009e0b6b761bd7425781d3d80dfe497eea9cfb9e822fde78aaddf2d0ab540153")

    def test_blackrock_mountain_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/brm")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertIn("art/simple/FP1_001.webp", files)
        self.assertFalse([p for p in files if p.startswith("art/") and ("/GVG_" in p or "/BRM_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/gvg.lua", "scripts/brm.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/brm"))
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        self.assertEqual(len([c for c in cards.values() if c["id"].startswith("BRM_") and c.get("collectible")]), 31)
        self.assertEqual(cards["FP1_028"]["script"], "scripts/brm.lua#FP1_028")  # Undertaker: +1 Attack (2.1.0.7628)
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertEqual(en["BRM_010a"]["text"], "Transform into a 5/2 minion.")  # the option's text of build 8311
        self.assertEqual(json.loads(files["manifest.json"])["rules_hash"],
                         "c8c9cd0dafb0dcc47aac4b573536154beb9705ec36dce19a7d7ac7fcb080f6eb")

    def test_the_grand_tournament_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/tgt")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/BRM_" in p or "/AT_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/gvg.lua", "scripts/brm.lua", "scripts/tgt.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/tgt"))
        rules = json.loads(files["rules.json"])
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": True, "full_hand_return_dies": True})
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        self.assertEqual(len([c for c in cards.values() if c["id"].startswith("AT_") and c.get("collectible")]), 132)
        self.assertEqual(len([c for c in cards.values() if c["id"].startswith("AT_") and not c.get("collectible")]), 26)
        self.assertEqual((cards["AT_132"]["cost"], cards["AT_132"]["health"]), (6, 3))  # Justicar until 2024
        self.assertEqual(cards["AT_132_MAGE"]["type"], "POWER")
        self.assertEqual(cards["BRM_017"]["script"], "scripts/tgt.lua#BRM_017")  # Resurrect (patch 3.0.0.9786)
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertEqual(en["AT_011"]["text"], "Whenever a character is healed, gain +2 Attack.")  # not the 2023 rework
        # a text an earlier pack of the chain overrode comes back as that day's
        self.assertEqual(en["BRM_020"]["text"], "Whenever <b>you</b> target this minion with a spell, gain +1/+1.")
        self.assertEqual(en["GVG_016"]["text"], "Whenever your opponent plays a card, remove the top 3 cards of your deck.")
        self.assertEqual(json.loads(files["manifest.json"])["rules_hash"],
                         "3a066714499915bc30a5625212e75033de81b391371cc85944c510159e0dfc9e")

    def test_the_league_of_explorers_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/loe")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/AT_" in p or "/LOE" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/gvg.lua", "scripts/brm.lua", "scripts/tgt.lua", "scripts/loe.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/loe"))
        rules = json.loads(files["rules.json"])
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": True, "full_hand_return_dies": True,
                                              "cost_in_order": True})
        self.assertEqual(rules["mechanics"]["DISCOVER"], {"engine": "OFFER"})
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        self.assertEqual(len([c for c in cards.values() if c.get("set") == "LOE" and c.get("collectible")]), 45)
        self.assertEqual(len([c for c in cards.values() if c.get("set") == "LOE" and not c.get("collectible")]), 15)
        self.assertEqual(cards["LOE_038"]["cost"], 5)  # Naga Sea Witch until 2018
        self.assertEqual(cards["LOE_051"]["race"], "BEAST")  # Jungle Moonkin until patch 11.4 (2018)
        self.assertEqual(cards["VAN_EX1_084"]["script"], "scripts/loe.lua#VAN_EX1_084")  # Warsong (3.2.0.10604)
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertEqual(en["VAN_EX1_084"]["text"], "Your <b>Charge</b> minions have +1 Attack.")
        self.assertEqual(en["LOE_110t"]["text"], "When you draw this, take 7 damage and draw a card.")
        self.assertEqual(cards["VAN_EX1_315"]["script"], "scripts/loe.lua#VAN_EX1_315")  # Summoning Portal comes first

    def test_whispers_of_the_old_gods_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/og")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/LOE" in p or "/OG_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/gvg.lua", "scripts/brm.lua", "scripts/tgt.lua", "scripts/loe.lua", "scripts/og.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/og"))
        rules = json.loads(files["rules.json"])
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": True, "full_hand_return_dies": True,
                                              "cost_in_order": True})
        self.assertEqual((rules["player_hooks"], rules["mechanics"]["CHOOSE_BOTH"]), ("player:og", {"engine": "BOTH_CHOICES"}))
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        self.assertEqual(len([c for c in cards.values() if c.get("set") == "OG" and c.get("collectible")]), 134)
        self.assertEqual((cards["OG_280"]["cost"], cards["VAN_EX1_620"]["cost"], cards["VAN_NEW1_019"]["attack"]), (10, 25, 2))
        self.assertEqual(cards["VAN_NEW1_014"]["script"], "scripts/og.lua#VAN_NEW1_014")  # Master of Disguise (5.0)
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertEqual(en["OG_302"]["text"], "Whenever a friendly minion dies, give your C'Thun +1/+1\n<i>(wherever it is).</i>")
        # Classic's own 2014 text of Sword of Justice gives way to that day's
        self.assertEqual(en["VAN_EX1_366"]["text"], "After you summon a minion, give it +1/+1 and this loses 1 Durability.")
        self.assertEqual(len([p for p in files if p.startswith("decks/")]), 16)

    def test_one_night_in_karazhan_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/kara")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/OG_" in p or "/KAR_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/loe.lua", "scripts/og.lua", "scripts/kara.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/kara"))
        rules = json.loads(files["rules.json"])
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": True, "full_hand_return_dies": True,
                                              "cost_in_order": True})
        self.assertEqual((rules["player_hooks"], rules["mechanics"]["UNLIMITED_ATTACKS"]),
                         ("player:kara", {"engine": "UNLIMITED_ATTACKS"}))
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        kara = [c for c in cards.values() if c.get("set") == "KARA"]
        self.assertEqual((len([c for c in kara if c.get("collectible")]), len(kara)), (45, 57))
        self.assertEqual((cards["KAR_114"]["cost"], cards["KAR_061"]["cost"], cards["KAR_076"]["cost"]), (4, 7, 7))
        self.assertEqual((cards["VAN_CS2_tk1"]["cost"], cards["VAN_EX1_tk9"]["cost"], cards["OG_034"]["race"]), (1, 2, "BEAST"))
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertEqual(en["OG_315"]["text"], "<b>Battlecry:</b> If you control another Pirate, give your weapon +1/+1.")
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 10)

    def test_mean_streets_of_gadgetzan_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/msg")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/KAR_" in p or "/CFM_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/og.lua", "scripts/kara.lua", "scripts/msg.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/msg"))
        rules = json.loads(files["rules.json"])
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": True, "full_hand_return_dies": True,
                                              "cost_in_order": True})
        self.assertEqual((rules["player_hooks"], rules["mechanics"]["RANDOM_TARGETS"], rules["mechanics"]["JADE_GOLEM"]),
                         ("player:msg", {"engine": "RANDOM_TARGETS"}, {"engine": "GROWING_SUMMON"}))
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        gangs = [c for c in cards.values() if c.get("set") == "GANGS"]
        self.assertEqual(len([c for c in gangs if c.get("collectible")]), 132)
        self.assertEqual((cards["CFM_621"]["class"], cards["CFM_621"]["classes"]), ("NEUTRAL", ["MAGE", "PRIEST", "WARLOCK"]))
        self.assertEqual(len([c for c in gangs if c.get("classes")]), 9)
        self.assertEqual((cards["VAN_CS2_103"]["cost"], cards["VAN_CS2_108"]["cost"], cards["VAN_CS2_188"]["attack"],
                          cards["OG_211"]["cost"]), (1, 2, 1, 9))
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertEqual(en["LOE_011"]["text"], "<b>Battlecry:</b> If your deck has no duplicates, fully heal your hero.")
        self.assertEqual(en["VAN_EX1_317"]["text"], "Draw 2 Demons\nfrom your deck.")
        # a deck of another class can't hold a tri-class card
        deck = {"name": "x", "champion": "HERO_01", "cards": ["CFM_621"] + ["VAN_CS2_182"] * 2 + ["VAN_CS2_231"] * 2 + 25 * ["?"]}
        self.assertEqual(pack.deck_error(dict(deck, cards=["CFM_621"]), cards, rules), "CFM_621 belongs to another class")
        self.assertIn("exactly", pack.deck_error(dict(deck, champion="HERO_08", cards=["CFM_621"]), cards, rules))
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 10)

    def test_journey_to_ungoro_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/ungoro")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/CFM_" in p or "/UNG_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg", "ungoro"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/kara.lua", "scripts/msg.lua", "scripts/ungoro.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/ungoro"))
        rules = json.loads(files["rules.json"])
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": True, "full_hand_return_dies": True,
                                              "cost_in_order": True})
        self.assertEqual((rules["player_hooks"], rules["mechanics"]["QUEST"], rules["mechanics"]["UNTOUCHABLE"]),
                         ("player:ungoro", {"engine": "TASK"}, {"engine": "DORMANT"}))
        self.assertIn("ELEMENTAL", rules["races"])
        self.assertEqual([r["rank"] for r in rules["ranked"]["ranks"] if r.get("floor")], [20, 15, 10, 5])  # patch 7.1
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        ungoro = [c for c in cards.values() if c.get("set") == "UNGORO"]
        self.assertEqual(len([c for c in ungoro if c.get("collectible")]), 135)
        self.assertEqual(len([c for c in ungoro if "QUEST" in c.get("keywords", [])]), 9)
        self.assertEqual((cards["VAN_EX1_298"]["race"], cards["CFM_325"]["health"], cards["KAR_063"]["cost"]),
                         ("ELEMENTAL", 1, 2))
        self.assertNotIn("race", cards["CFM_715"])  # Jade Spirit: an Elemental only from July 2017
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertEqual(en["UNG_067"]["text"], "[x]<b>Quest:</b> Play four minions\nwith the same name.\n<b>Reward:</b> Crystal Core.")
        self.assertIn("Poisonous", en["FP1_010"]["text"])  # Maexxna: the keyword since patch 7.1
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 10)

    def test_knights_of_the_frozen_throne_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/icc")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/UNG_" in p or "/ICC_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg", "ungoro", "icc"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/msg.lua", "scripts/ungoro.lua", "scripts/icc.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/icc"))
        rules = json.loads(files["rules.json"])
        # Un'Goro's flags stay (no patch changed them by then); a replaced weapon dies as any other
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": True, "full_hand_return_dies": True,
                                              "cost_in_order": True, "replaced_weapon_dies": True})
        self.assertEqual((rules["player_hooks"], rules["mechanics"]["LIFESTEAL"], rules["mechanics"]["EXTRA_END_TURN_EFFECT"]),
                         ("player:icc", {"engine": "LIFESTEAL"}, {"engine": "DOUBLE_TURN_END"}))
        self.assertIn({"id": "DEATHKNIGHT", "playable": False}, rules["classes"])
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        icc = [c for c in cards.values() if c.get("set") == "ICECROWN"]
        self.assertEqual(len([c for c in icc if c.get("collectible")]), 135)
        heroes = [c for c in icc if c["type"] == "CHAMPION" and c.get("collectible")]
        self.assertEqual(len(heroes), 9)
        self.assertTrue(all(c.get("armor") == 5 and c.get("power") for c in heroes))
        self.assertEqual((cards["ICC_054"]["cost"], cards["ICC_210"]["health"], cards["CFM_715"]["race"]), (5, 2, "ELEMENTAL"))
        self.assertIn("LIFESTEAL", cards["GVG_018"]["keywords"])
        en = json.loads(files["locales/en.json"])["cards"]
        self.assertIn("five minions", en["UNG_067"]["text"])  # patch 8.4
        self.assertIn("At the end", en["AT_019"]["text"])  # Dreadsteed, patch 9.0
        # a hero card goes into a deck of its class (Surrender's Jade Druid has Malfurion the Pestilent)
        deck = json.loads(files["decks/01_jade_druid.json"])
        self.assertIn("ICC_832", deck["cards"])
        self.assertEqual(pack.deck_error(deck, cards, rules), "")
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 10)

    def test_kobolds_and_catacombs_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/loot")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/ICC_" in p or "/LOOT_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg", "ungoro", "icc", "loot"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/ungoro.lua", "scripts/icc.lua", "scripts/loot.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/loot"))
        rules = json.loads(files["rules.json"])
        # patch 9.2: a countered spell is cast for after-spell hooks again, a minion a spell summons does not hear its
        # after-spell; patch 10.0: Lifesteal on several targets heals once
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": False, "full_hand_return_dies": True,
                                              "cost_in_order": True, "replaced_weapon_dies": True,
                                              "lifesteal_one_heal": True, "after_spell_from_before": True})
        self.assertEqual(rules["player_hooks"], "player:loot")
        self.assertEqual({k: rules["mechanics"][k]["engine"] for k in ("RECRUIT", "TOPDECK", "CANT_BE_TARGETED_BY_OPPONENTS")},
                         {"RECRUIT": "SUMMON_FROM_DECK", "TOPDECK": "CAST_WHEN_DRAWN", "CANT_BE_TARGETED_BY_OPPONENTS": "FOE_SPELLPROOF"})
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        loot = [c for c in cards.values() if c.get("set") == "LOOTAPALOOZA"]
        self.assertEqual(len([c for c in loot if c.get("collectible")]), 135)
        weapons = [c for c in loot if c.get("collectible") and c["type"] == "WEAPON" and c.get("rarity") == "LEGENDARY"]
        self.assertEqual(len(weapons), 9)  # one Legendary weapon per class
        self.assertEqual(cards["LOOT_306"]["cost"], 5)  # Possessed Lackey: 6 only from 2018-05
        for lang in ("en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"):
            loc = json.loads(files[f"locales/{lang}.json"])
            self.assertTrue(loc["sets"]["LOOTAPALOOZA"])
            self.assertTrue(all(loc["mechanics"][k].get("name") and loc["mechanics"][k].get("tip")
                                for k in ("RECRUIT", "CANT_BE_TARGETED_BY_OPPONENTS")), lang)
        en = json.loads(files["locales/en.json"])
        self.assertEqual((en["sets"]["LOOTAPALOOZA"], en["mechanics"]["RECRUIT"]["name"]), ("Kobolds & Catacombs", "Recruit"))
        self.assertEqual(en["cards"]["LOOT_051"]["text"], "Deal $2 damage to a minion. @<i>(Gain 3 Armor to upgrade.)</i>")
        self.assertEqual(en["cards"]["VAN_NEW1_010"]["text"], "<b>Charge, Divine Shield, Taunt, Windfury</b>")  # build 22611
        for f in [p for p in files if p.startswith("decks/")]:
            self.assertEqual(pack.deck_error(json.loads(files[f]), cards, rules), "", f)
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 10)

    def test_the_witchwood_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/gil")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/LOOT_" in p or "/GIL_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg", "ungoro", "icc", "loot", "gil"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/icc.lua", "scripts/loot.lua", "scripts/gil.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/gil"))
        rules = json.loads(files["rules.json"])
        # no behaviour changed between Kobolds & Catacombs and The Witchwood: the same flags
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": False, "full_hand_return_dies": True,
                                              "cost_in_order": True, "replaced_weapon_dies": True,
                                              "lifesteal_one_heal": True, "after_spell_from_before": True})
        self.assertEqual((rules["player_hooks"], rules["every_race"]), ("player:gil", "ALL"))
        self.assertEqual({k: rules["mechanics"][k]["engine"] for k in ("RUSH", "ECHO", "START_OF_GAME", "HERO_POWER_DOUBLE")},
                         {"RUSH": "QUICK", "ECHO": "REPEATABLE", "START_OF_GAME": "AT_GAME_START",
                          "HERO_POWER_DOUBLE": "POWER_DOUBLE"})
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        gil = [c for c in cards.values() if c.get("set") == "GILNEAS"]
        self.assertEqual(len([c for c in gil if c.get("collectible")]), 135)
        self.assertEqual(cards["GIL_191"]["cost"], 4)  # Fiendish Circle: 3 only from 2021
        self.assertEqual(cards["VAN_EX1_620"]["cost"], 20)  # Molten Giant: patch 11.0
        self.assertEqual((cards["LOOT_149"]["attack"], cards["ICC_705"]["cost"]), (2, 8))  # patch 10.2
        self.assertNotIn("keywords", cards["CFM_637"])  # Patches without Charge (patch 10.2)
        self.assertEqual(cards["LOE_051"]["race"], "BEAST")  # Jungle Moonkin: no tribe only from patch 11.4
        for lang in ("en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"):
            loc = json.loads(files[f"locales/{lang}.json"])
            self.assertTrue(loc["sets"]["GILNEAS"] and loc["races"]["ALL"])
            self.assertTrue(all(loc["mechanics"][k].get("name") and loc["mechanics"][k].get("tip")
                                for k in ("RUSH", "ECHO", "START_OF_GAME")), lang)
        en = json.loads(files["locales/en.json"])
        self.assertEqual((en["sets"]["GILNEAS"], en["mechanics"]["RUSH"]["name"]), ("The Witchwood", "Rush"))
        self.assertEqual(en["cards"]["VAN_EX1_393"]["text"], "Has +3 Attack while damaged.")  # Enrage retired (11.0)
        self.assertEqual(en["cards"]["VAN_EX1_595"]["text"], "After a friendly minion dies, draw a card.")
        for f in [p for p in files if p.startswith("decks/")]:
            self.assertEqual(pack.deck_error(json.loads(files[f]), cards, rules), "", f)
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 12)

    def test_the_boomsday_project_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/boom")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/GIL_" in p or "/BOT_" in p)])
        for s in ("basic", "classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg", "ungoro", "icc", "loot", "gil",
                  "boom"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/gil.lua", "scripts/boom.lua", "scripts/boom_cards.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/boom"))
        rules = json.loads(files["rules.json"])
        # The Witchwood's flags, and patch 12.0's transform rule
        self.assertEqual(rules["behaviour"], {"countered_no_after_spell": False, "full_hand_return_dies": True,
                                              "cost_in_order": True, "replaced_weapon_dies": True,
                                              "lifesteal_one_heal": True, "after_spell_from_before": True,
                                              "transform_drops_enchantments": True})
        self.assertEqual((rules["player_hooks"], rules["every_race"]), ("player:boom", "ALL"))
        self.assertEqual({k: rules["mechanics"][k]["engine"] for k in ("MODULAR", "HEALING_DOUBLE")},
                         {"MODULAR": "FUSE", "HEALING_DOUBLE": "HEAL_DOUBLE"})
        self.assertEqual(len(rules["deck_recipes"]["BOT_914"]), 18)
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        for d in rules["deck_recipes"]["BOT_914"]:
            self.assertEqual(len(d["cards"]), 30)
            self.assertTrue(all(c in cards and cards[c].get("collectible") for c in d["cards"]), d["about"])
        boom = [c for c in cards.values() if c.get("set") == "BOOMSDAY"]
        self.assertEqual(len([c for c in boom if c.get("collectible")]), 135)
        self.assertEqual(cards["BOT_270"]["cost"], 5)  # Giggling Inventor: 7 from 2018-10-18
        self.assertEqual((cards["BOT_238"]["armor"], cards["BOT_238"]["power"]), (7, "BOT_238p"))
        self.assertEqual([cards[c]["cost"] for c in ("LOOT_093", "LOOT_306", "LOOT_539", "LOE_038")], [5, 6, 7, 8])  # 11.1.1
        self.assertEqual(cards["VAN_EX1_105"]["race"], "ELEMENTAL")  # 11.4
        self.assertNotIn("race", cards["GIL_545"])  # 12.0
        self.assertEqual(cards["LOOT_017"]["script"], "scripts/boom.lua#LOOT_017")  # Dark Pact heals 4
        for lang in ("en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"):
            loc = json.loads(files[f"locales/{lang}.json"])
            self.assertTrue(loc["sets"]["BOOMSDAY"] and loc["classes"]["WHIZBANG"])
            self.assertTrue(loc["mechanics"]["MODULAR"].get("name") and loc["mechanics"]["MODULAR"].get("tip"), lang)
        en = json.loads(files["locales/en.json"])
        self.assertEqual((en["sets"]["BOOMSDAY"], en["mechanics"]["MODULAR"]["name"]), ("The Boomsday Project", "Magnetic"))
        self.assertEqual(en["cards"]["LOOT_017"]["text"], "Destroy a friendly minion. Restore #4 Health to your hero.")
        for f in [p for p in files if p.startswith("decks/")]:
            self.assertEqual(pack.deck_error(json.loads(files[f]), cards, rules), "", f)
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 12)

    def test_rastakhans_rumble_stands_alone(self):
        files, r = pack.build(pack.REPO / "packs/trl")
        self.assertEqual((r.errors, r.warnings), ([], []))
        self.assertFalse([p for p in files if p.startswith("art/") and ("/BOT_" in p or "/TRL_" in p)])
        for s in ("basic", "classic", "gil", "boom", "trl"):
            self.assertIn(f"ui/set_{s}.png", files)
        for f in ("scripts/boom.lua", "scripts/trl.lua"):
            self.assertIn(f, files)
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/trl"))
        rules = json.loads(files["rules.json"])
        boom = json.loads((pack.REPO / "packs/boom/rules.json").read_text())
        self.assertEqual(rules["behaviour"], boom["behaviour"])  # no patch of 12.2 to 13.0 changed a flag
        self.assertEqual((rules["player_hooks"], rules["mechanics"]["OVERKILL"]["engine"]), ("player:trl", "EXCESS_DAMAGE"))
        self.assertIn("TROLL", rules["modes"]["constructed"]["sets"])
        cards = {c["id"]: c for c in json.loads(files["cards.json"])}
        trl = [c for c in cards.values() if c.get("set") == "TROLL"]
        self.assertEqual(len([c for c in trl if c.get("collectible")]), 135)
        self.assertEqual([cards[c]["cost"] for c in ("VAN_NEW1_012", "BOT_270", "AT_045")], [2, 7, 10])  # 12.2.0.27358
        # the 4 Classic cards of patch 12.4.0.27405 (2018-11-05): first in this pack, filed under Classic
        for c in ("EX1_179", "EX1_180", "EX1_181", "EX1_182"):
            self.assertEqual((cards[c]["set"], cards[c].get("collectible")), ("VANILLA", True), c)
        self.assertEqual((cards["TRL_900"]["cost"], cards["TRL_900"]["attack"]), (5, 3))  # Halazzi: 4 mana 4/2 Rush in 2026
        for lang in ("en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"):
            loc = json.loads(files[f"locales/{lang}.json"])
            self.assertTrue(loc["sets"]["TROLL"] and loc["mechanics"]["OVERKILL"]["name"], lang)
        for f in [p for p in files if p.startswith("decks/")]:
            self.assertEqual(pack.deck_error(json.loads(files[f]), cards, rules), "", f)
        self.assertGreaterEqual(len([p for p in files if p.startswith("decks/")]), 12)

    def test_an_expansion_shows_the_texts_of_its_release_build(self):
        import extract_cards
        for s in [s for s in extract_cards.RELEASE_BUILDS if (pack.REPO / "packs" / s).is_dir()]:
            with self.subTest(s):
                self.assertEqual(release_text_gaps(s), {})


def release_text_gaps(s):
    """{lang: {card id: {field: text}}} where the built pack packs/<s> shows another card name or text than its hsjson
    step gives (the cards' data and the chain's cards.texts.json: the release build's, tools/extract_cards.py): a
    base pack's own locales/<lang>.json (Classic's 2014 texts) wins over them; restate these in packs/<s>/locales."""
    from extract_cards import _norm
    src = pack.REPO / "packs" / s
    files, _ = pack.build(src)
    pure = pack.Build(src)
    for root, step in pack.recipe_steps(src)[0]:
        if step["do"] == "hsjson":
            pack.step_hsjson(pure, root, step)
    gaps = {}
    for lang, loc in pure.locales.items():
        built = json.loads(files[f"locales/{lang}.json"])["cards"]
        for cid, fields in loc["cards"].items():
            for f, t in fields.items():
                if _norm(built.get(cid, {}).get(f)) != _norm(t):
                    gaps.setdefault(lang, {}).setdefault(cid, {})[f] = t
    return gaps


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

    def test_a_release_build_set_takes_todays_ids_and_marks_only(self):
        import extract_cards
        then = [{"id": "AT_011", "type": "MINION", "set": "TGT", "playerClass": "PRIEST", "cost": 4, "collectible": True,
                 "text": {"enUS": "Whenever a character is healed, gain +2 Attack."}},
                {"id": "AT_005t", "type": "MINION", "set": "TGT", "cost": 3}]
        now = [{"id": "AT_011", "type": "MINION", "set": "TGT", "cardClass": "PRIEST", "cost": 2, "dbfId": 2557,
                "mechanics": ["TRIGGER_VISUAL"], "referencedTags": ["OVERHEAL"], "text": {"enUS": "<b>Overheal:</b> Gain +2 Attack."}}]
        got = {c["id"]: c for c in extract_cards.release_cards(then, now)}
        self.assertEqual((got["AT_011"]["cost"], got["AT_011"]["dbfId"], got["AT_011"]["cardClass"]), (4, 2557, "PRIEST"))
        self.assertEqual(got["AT_011"]["mechanics"], ["TRIGGER_VISUAL"])
        self.assertNotIn("referencedTags", got["AT_011"])  # today's text differs: its tags are today's
        self.assertEqual(got["AT_005t"]["cardClass"], "NEUTRAL")


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


class Versions(unittest.TestCase):
    """A pack with versions (format.md §13): the view of a version, the checks, the builder from version patches."""

    def mega(self):
        """tiny() with versions a (as it is, the default) and b (M2 costs 4)."""
        base = as_files(tiny())
        cards = json.loads(base["cards.json"])
        cards[4]["cost"] = 4
        b = {**base, "cards.json": json.dumps(cards).encode()}
        files = {p: d for p, d in base.items() if not pack.is_version_file(p)}
        files.update(("versions/a/" + p, d) for p, d in base.items() if pack.is_version_file(p))
        files.update(("versions/b/" + p, d) for p, d in b.items() if pack.is_version_file(p))
        files.update((p, d) for p, d in base.items() if pack.is_version_file(p))
        files["art/x/M1.png"] = b"png"
        man = {**tiny()["manifest.json"], "art_sets": [{"id": "x"}], "default_version": "a", "versions": [
            {"id": "a", "dir": "versions/a", "rules_hash": pack.rules_hash(base)},
            {"id": "b", "dir": "versions/b", "rules_hash": pack.rules_hash(b), "formats": ["standard"]}]}
        man["rules_hash"] = man["versions"][0]["rules_hash"]
        files["manifest.json"] = json.dumps(man).encode()
        return files, b

    def test_a_view_is_the_shared_files_and_the_version(self):
        files, b = self.mega()
        self.assertEqual(pack.version_ids(files), ["a", "b"])
        self.assertEqual(pack.version_ids(as_files(tiny())), [])
        view = pack.version_view(files, "b")
        self.assertEqual(view["cards.json"], b["cards.json"])
        self.assertEqual(view["art/x/M1.png"], b"png")  # shared
        self.assertFalse([p for p in view if p.startswith("versions/")])
        self.assertEqual(json.loads(view["manifest.json"])["rules_hash"], pack.rules_hash(b))
        self.assertEqual(pack.rules_hash(view), pack.rules_hash(b))
        self.assertNotEqual(pack.rules_hash(view), pack.rules_hash(files))  # the top is the default version a
        self.assertEqual(pack.rules_hash(pack.version_view(files, "a")), pack.rules_hash(files))
        with self.assertRaises(pack.PackError):
            pack.version_view(files, "c")
        # a version without its own decks has none: the top's are the default version's
        del files["versions/b/decks/red.json"]
        self.assertNotIn("decks/red.json", pack.version_view(files, "b"))

    def test_every_version_is_checked(self):
        files, _ = self.mega()
        self.assertEqual(pack.check_files(files).errors, [])

        def errs(change):
            f = dict(files)
            change(f)
            return pack.check_files(f).errors
        self.assertTrue(any("versions/c/" in e for e in errs(lambda f: f.update({"versions/c/rules.json": b"{}"}))))
        self.assertTrue(any("versions/a/art" in e for e in errs(lambda f: f.update({"versions/a/art/x/M2.png": b"png"}))))
        cards = json.loads(files["versions/b/cards.json"])
        cards[4]["cost"] = 7  # the manifest's rules_hash of b is stale
        self.assertTrue(any(e.startswith("version b: ") and "rules_hash" in e
                            for e in errs(lambda f: f.update({"versions/b/cards.json": json.dumps(cards).encode()}))))
        self.assertTrue(any("not those of the default version" in e
                            for e in errs(lambda f: f.update({"cards.json": files["versions/b/cards.json"]}))))
        man = json.loads(files["manifest.json"])
        self.assertTrue(any("default_version" in e for e in errs(
            lambda f: f.update({"manifest.json": json.dumps({**man, "default_version": "z"}).encode()}))))

    def test_a_version_patch(self):
        vf = {"cards.json": pack.pretty([{"id": "A", "type": "MINION", "class": "GREY", "cost": 2, "keywords": ["WALL"]},
                                         {"id": "B", "type": "MINION", "class": "GREY", "cost": 1}]),
              "rules.json": pack.pretty({"limits": {}}),
              "locales/en.json": pack.pretty({"cards": {"A": {"name": "A", "text": "old"}, "B": {"name": "B"}}}),
              "locales/ru.json": pack.pretty({"cards": {"A": {"name": "А"}}}),
              "layout/en.json": pack.pretty({"A": {"lines": ["old"]}, "B": {"lines": ["b"]}})}
        patch = {"cards": {"A": {"cost": 5, "mechanics": [], "spellDamage": 1, "text": {"enUS": "new", "ruRU": "новый"}}},
                 "remove": ["B"], "add": [{"id": "N", "type": "HERO_POWER", "cardClass": "RED", "cost": 2,
                                          "name": {"enUS": "New", "ruRU": "Новая"}, "flavor": "x"}],
                 "behaviour": {"lifesteal_one_heal": True}}
        out = pack.apply_version_patch(dict(vf), patch, "p")
        cards = {c["id"]: c for c in json.loads(out["cards.json"])}
        self.assertEqual(cards["A"], {"id": "A", "type": "MINION", "class": "GREY", "cost": 5, "spell_power": 1})
        self.assertEqual(cards["N"], {"id": "N", "type": "POWER", "class": "RED", "cost": 2})
        self.assertNotIn("B", cards)
        en, ru = json.loads(out["locales/en.json"]), json.loads(out["locales/ru.json"])
        self.assertEqual((en["cards"]["A"]["text"], ru["cards"]["A"]["text"], ru["cards"]["N"]["name"]), ("new", "новый", "Новая"))
        self.assertNotIn("B", en["cards"])
        self.assertEqual(json.loads(out["layout/en.json"]), {})  # A's text changed, B is gone
        self.assertEqual(json.loads(out["rules.json"])["behaviour"], {"lifesteal_one_heal": True})
        with self.assertRaisesRegex(pack.PackError, "ruRU"):  # a text in every language of the pack
            pack.apply_version_patch(dict(vf), {"cards": {"A": {"text": {"enUS": "x"}}}}, "p")
        with self.assertRaisesRegex(pack.PackError, "no card Z"):
            pack.apply_version_patch(dict(vf), {"cards": {"Z": {"cost": 1}}}, "p")
        self.assertEqual(pack.apply_version_patch(dict(vf), {}, "p"), vf)  # an empty patch: the base as it is

    def test_building_from_version_patches(self):
        with tempfile.TemporaryDirectory() as t:
            t = Path(t)
            for p, v in as_files(tiny()).items():
                Chain.write(self, t / "base", p, v)
            Chain.write(self, t / "base", "art/x/M1.png", b"png")
            Chain.write(self, t / "base", "manifest.json", {**tiny()["manifest.json"], "art_sets": [{"id": "x"}]})
            Chain.write(self, t / "mega", "manifest.json", {**tiny()["manifest.json"], "id": "test.mega"})
            Chain.write(self, t / "mega", "recipe.json", {"default_version": "2", "versions": [
                {"id": "1", "date": "2014-01-01"}, {"id": "2", "name": {"en": "Two"}, "formats": ["standard"]}]})
            Chain.write(self, t / "mega", "versions/1/patch.json", {"base": "base", "build": 1})
            Chain.write(self, t / "mega", "versions/2/patch.json", {"base": "base", "build": 2, "cards": {"M2": {"cost": 4}}})
            Chain.write(self, t / "mega", "versions/2/scripts/fix.lua", b"return {}\n")
            files, r = pack.build(t / "mega")
            self.assertEqual(r.errors, [])
            man = json.loads(files["manifest.json"])
            self.assertEqual(man["id"], "test.mega")
            self.assertEqual(man["art_sets"], [{"id": "x"}])  # the bases' sets
            self.assertEqual([(v["id"], v["build"], v["dir"]) for v in man["versions"]],
                             [("1", 1, "versions/1"), ("2", 2, "versions/2")])
            self.assertEqual(man["versions"][0]["rules_hash"], pack.rules_hash(pack.build(t / "base")[0]))
            self.assertEqual(man["rules_hash"], man["versions"][1]["rules_hash"])
            v2 = pack.version_view(files, "2")
            self.assertEqual(next(c for c in json.loads(v2["cards.json"]) if c["id"] == "M2")["cost"], 4)
            self.assertEqual(v2["scripts/version/fix.lua"], b"return {}\n")
            self.assertIn("art/x/M1.png", files)
            self.assertNotIn("versions/1/art/x/M1.png", files)
            self.assertEqual(files["cards.json"], files["versions/2/cards.json"])  # the top is the default version
            self.assertFalse([p for p in files if "patch" in p or "recipe" in p])
            Chain.write(self, t / "mega", "versions/2/patch.json", {"base": "base", "cards": {"M2": {"text": {"deDE": "x"}}}})
            with self.assertRaises(pack.PackError):  # (a text without English)
                pack.build(t / "mega")

    def test_up_to_date_sees_the_bases(self):
        import os
        with tempfile.TemporaryDirectory() as t:
            out = Path(t) / "eras.cardpack"
            out.write_bytes(b"x")
            os.utime(out, (2e9, 2e9))  # newer than every file
            self.assertTrue(pack.up_to_date(pack.REPO / "packs/eras", out))
            inputs = pack._inputs(pack.REPO / "packs/eras")
            self.assertIn(pack.REPO / "packs/naxx", inputs)
            self.assertIn((pack.REPO / "packs/classic").resolve(), inputs)  # naxx's base


class Eras(unittest.TestCase):
    """packs/eras: Hearthstone 2014–2019 in one pack, a version per game version (packs/eras/README.md)."""

    @classmethod
    def setUpClass(cls):
        cls.files, cls.report = pack.build(pack.REPO / "packs/eras")
        cls.man = json.loads(cls.files["manifest.json"])

    def card(self, vid, cid):
        v = pack.version_view(self.files, vid)
        c = next(c for c in json.loads(v["cards.json"]) if c["id"] == cid)
        return c, {lang: json.loads(v[f"locales/{lang}.json"])["cards"][cid] for lang in self.man["locales"]}

    def test_it_builds_and_every_version_checks(self):
        self.assertEqual(self.report.errors, [])
        self.assertEqual(self.man["id"], "hs-eras")
        self.assertEqual(self.man["name"]["ru"], "Hearthstone 2014–2019: все версии")
        self.assertEqual(sorted(self.man["name"]), sorted(self.man["locales"]))
        ids = [v["id"] for v in self.man["versions"]]
        self.assertEqual(ids[:2], ["6024", "6485"])
        self.assertIn(self.man["default_version"], ids)
        for v in self.man["versions"]:
            self.assertEqual(sorted(v["name"]), sorted(self.man["locales"]), v["id"])
            self.assertEqual(v["rules_hash"], pack.rules_hash(pack.version_view(self.files, v["id"])))
        self.assertFalse(pack.bundle_in_client(pack.REPO / "packs/eras"))

    def test_6024_is_the_naxxramas_pack(self):
        naxx, _ = pack.build(pack.REPO / "packs/naxx")
        view = pack.version_view(self.files, "6024")
        self.assertEqual(pack.rules_hash(view), pack.rules_hash(naxx))
        self.assertEqual({p: d for p, d in view.items() if pack.is_version_file(p)},
                         {p: d for p, d in naxx.items() if pack.is_version_file(p)})
        self.assertEqual(self.card("6024", "VAN_EX1_116")[0]["cost"], 4)

    def test_6485_nerfs_leeroy_jenkins_and_starving_buzzard(self):
        leeroy, texts = self.card("6485", "VAN_EX1_116")
        self.assertEqual((leeroy["cost"], leeroy["attack"], leeroy["health"]), (5, 6, 2))
        self.assertEqual(texts["pl"]["text"], "<b>Szarża</b>. <b>Okrzyk bojowy:</b> Przyzwij dwa Pisklęta 1/1 swojemu przeciwnikowi.")
        buzzard, texts = self.card("6485", "VAN_CS2_237")
        self.assertEqual((buzzard["cost"], buzzard["attack"], buzzard["health"]), (5, 3, 2))
        self.assertEqual(texts["en"], {"name": "Starving Buzzard", "text": "Whenever you summon a Beast, draw a card."})
        self.assertEqual(texts["ru"]["text"], "Каждый раз, когда вы призываете зверя на поле боя, вы берете карту.")
        self.assertEqual(self.card("6024", "VAN_CS2_237")[0]["cost"], 2)


class ErasUngoro(unittest.TestCase):
    """packs/eras: the Journey to Un'Goro versions (18336, 19506, 19632, 20022)."""

    setUpClass = Eras.__dict__["setUpClass"]
    card = Eras.card

    def test_18336_is_the_ungoro_pack_with_the_msg_fixes(self):
        ungoro, _ = pack.build(pack.REPO / "packs/ungoro")
        view = pack.version_view(self.files, "18336")
        # the ungoro pack still has the Servant of Yogg-Saron, Mistcaller and Potion of Polymorph of before 15181, 15590 and
        # 17720: the fixes go along
        fixes = ["scripts/version/mistcaller.lua", "scripts/version/potion_of_polymorph.lua",
                 "scripts/version/servant_of_yogg_saron.lua"]
        self.assertEqual({p: d for p, d in view.items() if pack.is_version_file(p) and p not in fixes},
                         {p: d for p, d in ungoro.items() if pack.is_version_file(p)})
        for vid in ("18336", "19506", "19632", "20022"):
            for f in fixes:
                self.assertEqual(pack.version_view(self.files, vid)[f], pack.version_view(self.files, "17720")[f], vid)

    def test_19506_unbolds_dart_traps_hero_power(self):
        _, old = self.card("18336", "LOE_021")
        self.assertEqual(old["en"]["text"], "<b>Secret:</b> After an opposing <b>Hero Power</b> is used, deal $5 damage to a random enemy.")
        for vid in ("19506", "19632", "20022"):
            _, texts = self.card(vid, "LOE_021")
            self.assertEqual(texts["en"]["text"], "<b>Secret:</b> After an opposing Hero Power is used, deal $5 damage to a random enemy.")
            self.assertEqual(texts["ru"]["text"], "<b>Секрет:</b> когда противник использует силу героя, наносит $5 ед. урона случайному противнику.")
        # 19632 changed no card data
        self.assertEqual(pack.version_view(self.files, "19632")["cards.json"], pack.version_view(self.files, "19506")["cards.json"])

    def test_19506_and_20022_fix_names_and_texts_in_some_languages(self):
        self.assertEqual(self.card("18336", "CFM_690")[1]["ru"]["name"], "Нефритовый сюрикен")
        self.assertEqual(self.card("19506", "CFM_690")[1]["ru"]["name"], "Нефритовый сюрикэн")
        self.assertEqual(self.card("19506", "CFM_690")[1]["en"]["name"], "Jade Shuriken")
        self.assertEqual(self.card("18336", "UNG_961")[1]["fr"]["name"], "Acclimatation")
        for vid in ("19506", "19632", "20022"):
            self.assertEqual(self.card(vid, "UNG_961")[1]["fr"]["name"], "Adaptabilité", vid)
        self.assertEqual(self.card("19632", "VAN_CS2_039")[1]["es"]["name"], "Viento Furioso")
        self.assertEqual(self.card("20022", "VAN_CS2_039")[1]["es"]["name"], "Viento furioso")

    def test_20022_six_more_elementals(self):
        for cid in ("CFM_606", "CFM_606t", "CFM_715", "VAN_TU4e_002t", "LOE_053", "OG_209"):
            self.assertNotIn("race", self.card("19632", cid)[0], cid)
            self.assertEqual(self.card("20022", cid)[0]["race"], "ELEMENTAL", cid)

    def test_20022_the_caverns_below_needs_five_minions(self):
        _, old = self.card("19632", "UNG_067")
        _, new = self.card("20022", "UNG_067")
        self.assertEqual(old["en"]["text"], "[x]<b>Quest:</b> Play four minions\nwith the same name.\n<b>Reward:</b> Crystal Core.")
        self.assertEqual(new["en"]["text"], "[x]<b>Quest:</b> Play five minions\nwith the same name.\n<b>Reward:</b> Crystal Core.")
        self.assertEqual(new["de"]["text"], "<b>Quest:</b> Spielt 5 Diener mit dem gleichen Namen aus.\n<b>Belohnung:</b> Kristallkern")
        self.assertIn("scripts/version/ungoro.lua", pack.version_view(self.files, "20022"))
        self.assertNotIn("scripts/version/ungoro.lua", pack.version_view(self.files, "19632"))


class ErasMsg(unittest.TestCase):
    """packs/eras: the versions of the Mean Streets of Gadgetzan era (15590, 16214, 17720), each from the msg pack."""

    @classmethod
    def setUpClass(cls):
        cls.files, cls.report = pack.build(pack.REPO / "packs/eras")
        cls.man = json.loads(cls.files["manifest.json"])

    card = Eras.card

    def test_the_versions_and_their_scripts(self):
        self.assertEqual(self.report.errors, [])
        ids = [v["id"] for v in self.man["versions"]]
        self.assertLess(ids.index("15590"), ids.index("16214"))
        self.assertLess(ids.index("16214"), ids.index("17720"))
        msg, _ = pack.build(pack.REPO / "packs/msg")
        views = {vid: pack.version_view(self.files, vid) for vid in ("15590", "16214", "17720")}
        # 15590 and 16214 are the msg pack's cards and texts; only their scripts differ
        for vid in ("15590", "16214"):
            for p, d in msg.items():
                if pack.is_version_file(p) and not p.startswith("scripts/"):
                    self.assertEqual(views[vid].get(p), d, f"{vid} {p}")
        scripts = {vid: sorted(p for p in v if p.startswith("scripts/version/")) for vid, v in views.items()}
        S = "scripts/version/servant_of_yogg_saron.lua"  # 15181's fix: the msg pack keeps og.lua's Servant
        self.assertEqual(scripts, {"15590": ["scripts/version/kabal_chemist.lua", "scripts/version/mistcaller.lua", S],
                                   "16214": ["scripts/version/mistcaller.lua", S],
                                   "17720": ["scripts/version/mistcaller.lua", "scripts/version/potion_of_polymorph.lua", S]})

    def test_17720_nerfs_small_time_buccaneer_and_spirit_claws(self):
        for vid, hp, cost in (("16214", 2, 1), ("17720", 1, 2)):
            self.assertEqual(self.card(vid, "CFM_325")[0]["health"], hp, vid)
            self.assertEqual(self.card(vid, "KAR_063")[0]["cost"], cost, vid)
        self.assertEqual(self.card("16214", "CFM_025")[0]["keywords"], ["CHOOSE_ONE", "TRIGGER_VISUAL"])
        self.assertEqual(self.card("17720", "CFM_025")[0]["keywords"], ["TRIGGER_VISUAL"], "Wind-up Burglebot")

    def test_17720_writes_poisonous_and_rewords(self):
        for cid in ("VAN_EX1_170", "FP1_010", "LOE_010"):
            old, new = self.card("16214", cid)[1], self.card("17720", cid)[1]
            self.assertEqual(old["en"]["text"], "Destroy any minion damaged by this minion.", cid)
            self.assertEqual(new["en"]["text"], "<b>Poisonous</b>", cid)
            self.assertEqual(new["ru"]["text"], "<b>Яд</b>", cid)
        self.assertEqual(self.card("17720", "VAN_EX1_522")[1]["en"]["text"], "<b>Stealth</b>\n <b>Poisonous</b>")
        self.assertEqual(self.card("16214", "VAN_NEW1_016")[1]["en"]["text"],
                         "<b>Battlecry:</b> Put a random Pirate from your deck into your hand.")
        parrot = self.card("17720", "VAN_NEW1_016")[1]
        self.assertEqual(parrot["en"]["text"], "<b>Battlecry:</b> Draw a Pirate from your deck.")
        self.assertEqual(parrot["de"]["text"], "<b>Kampfschrei:</b> Zieht einen Piraten aus Eurem Deck.")
        self.assertEqual(self.card("17720", "BRM_005")[1]["en"]["text"], "[x]Deal $2 damage to all\nminions except Demons.")
        # every text of the patch is in 17720 and differs from 16214's in some language
        patch = json.loads((pack.REPO / "packs/eras/versions/17720/patch.json").read_text())
        for cid, ch in patch["cards"].items():
            old, new = self.card("16214", cid)[1], self.card("17720", cid)[1]
            for f in ("name", "text"):
                if f in ch:
                    self.assertEqual({lang: new[lang][f] for lang in new}, {lang: ch[f][hs] for lang, hs in pack.HS_LOCALES.items()}, cid)
                    self.assertNotEqual({lang: old[lang][f] for lang in old}, {lang: new[lang][f] for lang in new}, cid)


class ErasIcc(unittest.TestCase):
    """packs/eras: the Knights of the Frozen Throne versions (20457, 20970, 21517, 22115) on the icc pack."""

    setUpClass = classmethod(Eras.setUpClass.__func__)
    card = Eras.card

    def rules(self, vid):
        return json.loads(pack.version_view(self.files, vid)["rules.json"])

    def test_20457_is_the_frozen_throne_pack_with_the_msg_fixes(self):
        icc, _ = pack.build(pack.REPO / "packs/icc")
        view = pack.version_view(self.files, "20457")
        # the icc pack still has the Servant of Yogg-Saron, Mistcaller and Potion of Polymorph of before 15181, 15590 and
        # 17720: the fixes go along
        fixes = ["scripts/version/mistcaller.lua", "scripts/version/potion_of_polymorph.lua",
                 "scripts/version/servant_of_yogg_saron.lua"]
        self.assertEqual({p: d for p, d in view.items() if pack.is_version_file(p) and p not in fixes},
                         {p: d for p, d in icc.items() if pack.is_version_file(p)})
        for vid in ("20457", "20970", "21517", "22115"):
            for f in fixes:
                self.assertEqual(pack.version_view(self.files, vid)[f], pack.version_view(self.files, "17720")[f], vid)
        self.assertEqual([v["era"] for v in self.man["versions"] if v["id"] in ("20457", "20970", "21517", "22115")],
                         ["icc"] * 4)

    def test_20970_nerfs(self):
        for vid in ("20970", "21517", "22115"):  # each version is the icc pack and all the changes up to it
            for cid, old, new in (("ICC_054", 5, 6), ("VAN_CS2_106", 2, 3), ("VAN_EX1_246", 3, 4)):
                self.assertEqual(self.card("20457", cid)[0]["cost"], old, cid)
                self.assertEqual(self.card(vid, cid)[0]["cost"], new, (vid, cid))
            _, texts = self.card(vid, "VAN_EX1_169")
            self.assertEqual(texts["en"]["text"], "Gain 1 Mana Crystal this turn only.")
            self.assertEqual(texts["pl"]["text"], "Otrzymujesz 1 kryształ many w tej turze.")
            _, texts = self.card(vid, "VAN_EX1_507")
            self.assertEqual(texts["en"]["text"], "Your other Murlocs have +2 Attack.")
            self.assertEqual(texts["de"]["text"], "Eure anderen Murlocs haben +2 Angriff.")
        _, texts = self.card("20457", "VAN_EX1_169")
        self.assertEqual(texts["en"]["text"], "Gain 2 Mana Crystals this turn only.")
        self.assertEqual(self.card("20457", "VAN_EX1_507")[1]["ru"]["text"], "Другие ваши мурлоки получают +2/+1.")
        # wording of that build: Dreadsteed (de), Forbidden Healing (es)
        self.assertEqual(self.card("20970", "AT_019")[1]["de"]["text"],
                         "<b>Todesröcheln:</b> Beschwört am Ende des Zuges ein Schreckensross.")
        self.assertEqual(self.card("20970", "OG_198")[1]["es"]["text"],
                         "Gasta todo tu maná. Restaura el doble de esa cantidad en salud.")
        self.assertEqual(self.card("20970", "OG_198")[1]["en"], self.card("20457", "OG_198")[1]["en"])

    def test_21517_mechanics_update(self):
        _, texts = self.card("21517", "CFM_900")
        self.assertEqual(texts["en"]["text"], "After you summon a minion, deal 5 damage to your hero.")
        self.assertEqual(texts["es"]["text"], "[x]Tras invocar a un esbirro,\ninflige 5 p. de daño\na tu héroe.")
        self.assertEqual(self.card("20970", "CFM_900")[1]["en"]["text"],
                         "Whenever you summon a minion, deal 5 damage to your hero.")
        self.assertEqual(self.card("21517", "ICC_812")[1]["it"]["name"], "Carro dei Morti")
        self.assertEqual(self.card("20970", "ICC_812")[1]["it"]["name"], "Carro della Carne")
        self.assertEqual(self.card("21517", "VAN_EX1_154")[1]["en"]["text"],
                         "<b>Choose One -</b>\nDeal $3 damage to a minion; or $1 damage\nand draw a card.")
        # the texts of that build (wording, spaces, line breaks) for the rest
        for cid, lang in (("AT_050", "de"), ("AT_065", "en"), ("CFM_659", "fr"), ("GVG_111", "de"), ("ICC_064", "en"),
                          ("ICC_834w", "en"), ("KAR_021", "fr"), ("OG_338", "fr"), ("UNG_934t1", "en"),
                          ("VAN_EX1_557", "fr"), ("VAN_NEW1_007", "en")):
            self.assertNotEqual(self.card("21517", cid)[1][lang], self.card("20970", cid)[1][lang], cid)
        self.assertEqual(self.card("21517", "AT_065")[1]["en"]["text"],
                         "<b>Battlecry:</b> If you have a minion with <b>Taunt</b>, gain +1 Durability.")
        for vid, after in (("20457", True), ("20970", True), ("21517", False), ("22115", False)):
            beh = self.rules(vid)["behaviour"]
            self.assertEqual(beh.get("countered_no_after_spell", False), after, vid)  # Counterspell
            self.assertEqual(beh.get("after_spell_from_before", False), not after, vid)  # Wild Pyromancer, Mindgames
            self.assertFalse(beh.get("lifesteal_one_heal", False), vid)  # Kobolds & Catacombs'

    def test_22115_marin_the_fox(self):
        marin, texts = self.card("22115", "LOOT_357")
        self.assertEqual((marin["cost"], marin["attack"], marin["health"]), (8, 6, 6))
        self.assertEqual((marin["set"], marin["rarity"], marin["collectible"]), ("LOOTAPALOOZA", "LEGENDARY", True))
        self.assertEqual(marin["script"], "scripts/version/marin.lua#LOOT_357")
        self.assertEqual(texts["en"]["name"], "Marin the Fox")
        self.assertEqual(texts["ru"]["name"], "Марин Лис")
        self.assertIn("Treasure Chest", texts["en"]["text"])
        chest, texts = self.card("22115", "LOOT_357l")
        self.assertEqual((chest["cost"], chest["attack"], chest["health"], chest["keywords"]), (3, 0, 8, ["DEATHRATTLE"]))
        self.assertEqual(texts["en"]["text"], "<b>Deathrattle:</b> Give your opponent a fantastic Treasure.")
        self.assertEqual(self.card("22115", "LOOT_998l")[1]["en"]["text"], "Draw 3 cards. They cost (0).")
        self.assertEqual(self.card("22115", "LOOT_998l")[1]["fr"]["name"], "Baguette miraculeuse")
        for cid in ("LOOT_998h", "LOOT_998j", "LOOT_998k"):
            self.assertIn("scripts/version/marin.lua#", self.card("22115", cid)[0]["script"])
        early = json.loads(pack.version_view(self.files, "21517")["cards.json"])
        self.assertFalse([c["id"] for c in early if c["id"].startswith("LOOT_")])
        # Kobolds & Catacombs' set: known, and in constructed decks (Marin was given to every player); not in Arena
        rules = self.rules("22115")
        self.assertIn("LOOTAPALOOZA", rules["sets"])
        self.assertIn("LOOTAPALOOZA", rules["modes"]["constructed"]["sets"])
        self.assertNotIn("LOOTAPALOOZA", rules["modes"]["arena"]["sets"])
        self.assertNotIn("LOOTAPALOOZA", self.rules("21517")["sets"])
        # wording of that build: Dire Shapeshift (es)
        self.assertEqual(self.card("22115", "AT_132_DRUID")[1]["es"]["text"],
                         "<b>Poder de héroe</b>\nObtienes +2 p. de ataque este turno y +2 p. de armadura.")
        self.assertEqual(self.card("22115", "VAN_HERO_06bp2")[1]["es"]["text"],
                         self.card("22115", "AT_132_DRUID")[1]["es"]["text"])


class ErasKara(unittest.TestCase):
    """packs/eras, the One Night in Karazhan era (base packs/kara): 13921, 14366, 14830, 15181."""

    @classmethod
    def setUpClass(cls):
        cls.files, cls.report = pack.build(pack.REPO / "packs/eras")
        cls.man = json.loads(cls.files["manifest.json"])
        cls.views = {}

    def view(self, vid):
        if vid not in self.views:
            self.views[vid] = pack.version_view(self.files, vid)
        return self.views[vid]

    def card(self, vid, cid):
        v = self.view(vid)
        c = next(c for c in json.loads(v["cards.json"]) if c["id"] == cid)
        return c, {lang: json.loads(v[f"locales/{lang}.json"])["cards"][cid] for lang in self.man["locales"]}

    def test_the_versions_are_listed(self):
        self.assertEqual(self.report.errors, [])
        vs = {v["id"]: v for v in self.man["versions"]}
        for vid in ("13921", "14366", "14830", "15181"):
            self.assertEqual((vs[vid]["era"], vs[vid]["formats"]), ("kara", ["standard", "wild"]), vid)
        self.assertEqual(vs["14830"]["name"]["ru"], "Ослаблены Йогг-Сарон, Зов лесов, Рывок и ещё четыре карты")

    def test_13921_is_the_karazhan_pack(self):
        kara, _ = pack.build(pack.REPO / "packs/kara")
        view = self.view("13921")
        self.assertEqual(pack.rules_hash(view), pack.rules_hash(kara))
        self.assertEqual({p: d for p, d in view.items() if pack.is_version_file(p)},
                         {p: d for p, d in kara.items() if pack.is_version_file(p)})

    def test_14366_fixes_texts_only(self):
        self.assertEqual(pack.rules_hash(self.view("14366")), pack.rules_hash(self.view("13921")))
        old, new = self.card("13921", "GVG_107")[1], self.card("14366", "GVG_107")[1]
        self.assertTrue(old["en"]["text"].endswith("<b>Divine Shield</b>.\n<i>(at random)</i>"))
        self.assertTrue(new["en"]["text"].endswith("<b>Divine Shield</b>\n<i>(at random)</i>."))
        self.assertTrue(new["fr"]["text"].endswith("<i>(au hasard)</i>."))
        self.assertEqual(self.card("13921", "AT_050")[1]["ru"]["text"][:28], "<b>Предсмертный хрип:</b> Си")
        self.assertEqual(self.card("14366", "AT_050")[1]["ru"]["text"][:28], "<b>Предсмертный хрип:</b> си")
        self.assertEqual(self.card("14366", "AT_050")[1]["en"], self.card("13921", "AT_050")[1]["en"])

    def test_14830_nerfs(self):
        for cid, field, old, new in [("VAN_CS2_045", "cost", 1, 2), ("VAN_CS2_108", "cost", 1, 2), ("OG_211", "cost", 8, 9),
                                     ("VAN_CS2_103", "cost", 3, 1), ("VAN_CS2_188", "attack", 2, 1)]:
            self.assertEqual(self.card("14366", cid)[0][field], old, cid)
            self.assertEqual(self.card("14830", cid)[0][field], new, cid)
            self.assertEqual(self.card("15181", cid)[0][field], new, cid)
        charge = self.card("14830", "VAN_CS2_103")[1]
        self.assertEqual(charge["en"]["text"], "Give a friendly minion <b>Charge</b>. It can't attack heroes this turn.")
        self.assertEqual(charge["ru"]["text"], "Ваше выбранное существо получает <b>«Рывок»</b>. На этом ходу оно не может атаковать героев.")
        self.assertEqual(self.card("14366", "VAN_CS2_103")[1]["en"]["text"], "Give a friendly minion +2 Attack and <b>Charge</b>.")
        tuskarr = self.card("14830", "AT_046")[1]
        self.assertEqual(tuskarr["en"]["text"], "<b>Battlecry:</b> Summon a random basic Totem.")
        self.assertEqual(tuskarr["de"]["text"], "<b>Kampfschrei:</b> Beschwört ein zufälliges Basistotem.")
        self.assertEqual(self.card("14366", "AT_046")[1]["en"]["text"], "<b>Battlecry:</b> Summon ANY random Totem.")
        self.assertIn("scripts/version/kara_6_1_3.lua", self.view("14830"))
        self.assertNotIn("scripts/version/kara_6_1_3.lua", self.view("14366"))

    def test_15181_murlocs_peddler_and_texts(self):
        for cid, en, de in [("VAN_EX1_507", "Your other Murlocs have +2/+1.", "Eure anderen Murlocs haben +2/+1."),
                            ("VAN_EX1_508", "Your other Murlocs have +1 Attack.", "Eure anderen Murlocs haben +1 Angriff."),
                            ("VAN_EX1_103", "<b>Battlecry:</b> Give your other Murlocs +2 Health.", "<b>Kampfschrei:</b> Verleiht Euren anderen Murlocs +2 Leben."),
                            ("VAN_EX1_509", "Whenever you summon a Murloc, gain +1 Attack.", "Erhält jedes Mal +1 Angriff, wenn Ihr einen Murloc herbeiruft.")]:
            texts = self.card("15181", cid)[1]
            self.assertEqual((texts["en"]["text"], texts["de"]["text"]), (en, de), cid)
            self.assertNotEqual(self.card("14830", cid)[1]["en"]["text"], en, cid)
        peddler = self.card("15181", "KAR_070")[1]
        self.assertEqual(peddler["en"]["text"], "[x]<b>Battlecry:</b> If you're holding\nany non-Rogue class cards,\n reduce their Cost by (2).")
        self.assertEqual(peddler["it"]["text"], "<b>Grido di Battaglia:</b> riduce di (2) il costo delle carte non del Ladro nella tua mano.")
        self.assertEqual(self.card("14830", "KAR_070")[1]["en"]["text"], "[x]<b>Battlecry:</b> Reduce the Cost\nof cards in your hand from\nother classes by (2).")
        self.assertEqual(self.card("15181", "VAN_EX1_533")[1]["en"]["text"], "<b>Secret:</b> When a character attacks your hero, instead they attack another random character.")
        # Elemental Destruction's Overload 1 in this build's data is export noise: it stays 5
        ed = self.card("15181", "AT_051")
        self.assertEqual((ed[0]["mana_lock"], ed[1]["en"]["text"]), (5, "Deal $4-$5 damage to all minions. <b>Overload:</b> (5)"))
        self.assertEqual(self.card("14830", "AT_051")[1]["en"]["text"], "Deal $4-$5 damage to all minions. <b>Overload:</b> (5).")
        self.assertEqual(self.card("15181", "VAN_CS2_188")[1]["en"]["text"], "<b>Battlecry:</b> Give a minion +2 Attack this turn.")
        self.assertIn("scripts/version/kara_6_2.lua", self.view("15181"))
        self.assertNotIn("scripts/version/kara_6_1_3.lua", self.view("15181"))


class TestDistribution(unittest.TestCase):
    """The expansions stay out of the game's builds (APK, desktop, web): release files and the server's."""

    def test_only_the_three_first_games_are_in_the_client(self):
        srcs = [d for d in sorted((pack.REPO / "packs").iterdir()) if (d / "manifest.json").exists()]
        # without .gdignore Godot imports a source folder's pictures and every export carries them
        self.assertEqual([d.name for d in srcs if not (d / ".gdignore").exists()], [])
        # a bundled pack goes into res://packs and so into every build (the web .pck must stay under 95 MB)
        self.assertEqual([d.name for d in srcs if pack.bundle_in_client(d)], ["classic", "naxx", "neon"])

    def test_the_release_and_the_server_take_build_packs(self):
        root = pack.REPO
        self.assertIn("build/packs/*.cardpack", (root / "tools/export_all.sh").read_text())  # release assets
        self.assertIn("COPY build/packs/ /packs/", (root / "server/Dockerfile").read_text())
        ignore = (root / "server/Dockerfile.dockerignore").read_text().split()
        for need in ("!build/packs", "!packs/*.cardpack", "!rust/brain", "!project.godot"):
            self.assertIn(need, ignore)
        filters = [ln for ln in (root / "export_presets.cfg").read_text().splitlines() if ln.startswith("include_filter")]
        self.assertEqual([ln for ln in filters if "build/" in ln], [])  # no export takes the expansions


if __name__ == "__main__":
    unittest.main()
