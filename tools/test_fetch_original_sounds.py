"""Tests of tools/fetch_original_sounds.py (offline, Cargo rows as fixtures):
python3 -m unittest tools/test_fetch_original_sounds.py (from the repo root)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_original_sounds as snd  # noqa: E402

SEARING = {"BASIC attack": "SFX_CS2_050_Attack_00.wav", "BASIC attack underlay": ""}
FOOTMAN = {"BASIC attack": "VO_CS1_042_Attack_02.wav", "BASIC attack underlay": ""}


class Namesakes(unittest.TestCase):
    def test_a_silent_minion_takes_its_namesakes_attack(self):
        cards = [("AT_132_SHAMANb", "MINION"), ("AT_132_SHAMANd", "MINION"), ("CS1_042", "MINION"),
                 ("CS2_029", "SPELL")]
        rows = {"AT_132_SHAMANb": {}, "AT_132_SHAMANd": {}, "CS1_042": FOOTMAN, "CS2_029": {}}
        names = {"AT_132_SHAMANb": "Searing Totem", "CS2_050": "Searing Totem", "VAN_CS2_050": "Searing Totem",
                 "AT_132_SHAMANd": "Wrath of Air Totem", "CS2_052": "Wrath of Air Totem", "CS1_042": "Goldshire Footman",
                 "VAN_CS1_042": "Goldshire Footman", "CS2_029": "Fireball", "EX1_FB": "Fireball"}
        asked = []

        def more(ids):
            asked.append(sorted(ids))
            return {i: {"CS2_050": SEARING, "VAN_CS2_050": SEARING}.get(i, {}) for i in ids}
        got = snd.namesakes(cards, rows, names, more)
        self.assertEqual(got, {"AT_132_SHAMANb": [("set", "AT_132_SHAMANb_attack", "SFX_CS2_050_Attack_00.wav")]})
        self.assertEqual(asked, [["CS2_050", "CS2_052", "VAN_CS2_050"]])  # (only silent minions' namesakes, once)

    def test_not_a_numbered_token(self):  # (fetch_card_sounds.inherited gives Jade Golem t05 its t04's sounds)
        names = {"CFM_712_t05": "Jade Golem", "CFM_712_t01": "Jade Golem"}
        got = snd.namesakes([("CFM_712_t05", "MINION")], {}, names, lambda ids: {i: SEARING for i in ids})
        self.assertEqual(got, {})

    def test_the_line_comes_too(self):
        cards = [("TU4a_009", "MINION")]
        names = {"TU4a_009": "Goldshire Footman", "CS1_042": "Goldshire Footman"}
        got = snd.namesakes(cards, {"TU4a_009": {}}, names, lambda ids: {i: FOOTMAN for i in ids})
        self.assertEqual(got, {"TU4a_009": [("voice", "TU4a_009_attack", "VO_CS1_042_Attack_02.wav")]})


class RussianIndex(unittest.TestCase):
    def test_another_sets_line(self):
        with tempfile.TemporaryDirectory() as t:
            cache = Path(t)
            (cache / "ru_index.json").write_text(json.dumps({"vo_ex1_298_attack_02.wav": "classic-id"}))
            (cache / "ru_index_trl.json").write_text(json.dumps({"vo_trl_010_play_01.wav": "trl-id"}))
            (cache / "ru_index_dal.json").write_text(json.dumps({"vo_trl_010_play_01.wav": "dal-id"}))
            ru = snd.ru_for("trl", cache)
        self.assertEqual(ru["vo_ex1_298_attack_02.wav"], "classic-id")  # (Rastakhan's Ragnaros token: EX1_298's line)
        self.assertEqual(ru["vo_trl_010_play_01.wav"], "trl-id")  # (the set's own index wins)


if __name__ == "__main__":
    unittest.main()
