"""Tests of tools/check_sounds.py's rules (offline: no network, no Blizzard files):
python3 -m unittest tools/test_check_sounds.py (from the repo root)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_sounds as cs  # noqa: E402
import fetch_original_sounds as snd  # noqa: E402

IDS = {"OG_042", "OG_133", "GVG_110", "GVG_110t", "LOEA10_3", "VAN_EX1_116", "HERO_08", "TU4a_006", "EX1_323",
       "EX1_323h"}
UPPER = {i.removeprefix("VAN_").upper(): i.removeprefix("VAN_") for i in IDS}
NAMES = {cs.norm("Leeroy Jenkins"): "EX1_116", cs.norm("N'Zoth, the Corruptor"): "OG_133",
         cs.norm("Y'Shaarj, Rage Unbound"): "OG_042"}
NAME_OF = {"HERO_08": cs.norm("Jaina Proudmoore"), "TU4a_006": cs.norm("Jaina Proudmoore")}


def owner(src, cid, name, tables=frozenset()):
    return cs.belongs(src, cid, name, UPPER, NAMES, tables, NAME_OF)[0]


class Names(unittest.TestCase):
    def test_longest_id_wins(self):
        self.assertEqual(cs.parse_name("GVG_110t_play", IDS), ("GVG_110t", "play", True))
        self.assertEqual(cs.parse_name("GVG_110_music", IDS), ("GVG_110", "music", True))

    def test_roles(self):
        self.assertTrue(cs.parse_name("LOEA10_3_hit_3", IDS)[2])
        self.assertFalse(cs.parse_name("OG_042_boom", IDS)[2])
        self.assertEqual(cs.parse_name("spell_fire", IDS), (None, None, False))

    def test_voice_kinds(self):
        self.assertTrue(cs.parse_name("HERO_08_error_need_mana", IDS, voice=True)[2])
        self.assertTrue(cs.parse_name("HERO_08_well_played", IDS, voice=True)[2])
        self.assertFalse(cs.parse_name("HERO_08_aim", IDS, voice=True)[2])


class Roles(unittest.TestCase):
    def test_words(self):
        self.assertEqual(cs.words("FX_Minion_AttackImpactLarge.wav"), ["fx", "minion", "attack", "impact", "large"])
        self.assertIn("enter", cs.words("VO_FP1_001_EnterPlay_01.wav"))

    def test_agreement(self):
        self.assertTrue(cs.role_agrees("play", "GVG_110_DrBoom_Play.wav"))
        self.assertFalse(cs.role_agrees("death", "GVG_110_DrBoom_Play.wav"))
        self.assertFalse(cs.role_agrees("play", "X_Attack_Underlay.wav"))
        self.assertFalse(cs.role_agrees("play", "Shared_Fire_Impact.wav"))
        self.assertTrue(cs.role_agrees("hit_2", "Shared_Fire_Impact.wav"))
        self.assertTrue(cs.role_agrees("death", "Minion_Death_01.wav"))
        self.assertTrue(cs.role_agrees("music", "YShaarj_Play_Stinger.wav"))
        self.assertTrue(cs.role_agrees("aim", "Some_Neutral_Name.wav"))
        self.assertTrue(cs.role_agrees("trigger", "LeperGnome_DeathRattle_Cast_1.wav"))
        self.assertTrue(cs.role_agrees("reveal", "WhiteEyes_SpawnToDeck_CustomReveal_Sound.wav"))
        self.assertFalse(cs.role_agrees("trigger", "X_Attack_Underlay.wav"))
        self.assertTrue(cs.role_agrees("hit", "Crush_CustomDeath_Sound_01.wav"))

    def test_voice_agreement(self):
        self.assertFalse(cs.role_agrees("death", "VO_CFM_810_Female_Quilboar_Attack_02.wav", voice=True))
        self.assertTrue(cs.role_agrees("play", "VO_FP1_001_EnterPlay_01.wav", voice=True))
        self.assertTrue(cs.role_agrees("greetings", "VO_HERO_08_Attack_71.wav", voice=True))


class Owner(unittest.TestCase):
    def test_own_id_and_name(self):
        self.assertEqual(owner("GVG_110_DrBoom_Play.wav", "GVG_110", "Dr. Boom"), "ok")
        self.assertEqual(owner("VO_EX1_116_Play_01.wav", "VAN_EX1_116", "Leeroy Jenkins"), "ok")
        self.assertEqual(owner("Pegasus_Stinger_Leeroy_Jenkins.wav", "VAN_EX1_116", "Leeroy Jenkins"), "ok")
        self.assertEqual(owner("YShaarj_Play_Stinger.wav", "OG_042", "Y'Shaarj, Rage Unbound"), "ok")
        self.assertEqual(owner("Banana_Impact_Sound.wav", "EX1_014t", "Bananas"), "ok")

    def test_another_cards_voice_is_an_error(self):
        self.assertEqual(owner("VO_OG_133_Male_OldGod_Play_01.wav", "OG_042", "Y'Shaarj, Rage Unbound"), "error")
        self.assertEqual(owner("OG_133_Something_Play.wav", "OG_042", "Y'Shaarj, Rage Unbound"), "flag")

    def test_related_and_same_character(self):
        self.assertEqual(owner("VO_EX1_323_Attack_02.wav", "EX1_323h", "Lord Jaraxxus"), "info")
        self.assertEqual(owner("VO_HERO_08_Greetings_56.wav", "TU4a_006", "Jaina Proudmoore"), "info")

    def test_shared(self):
        self.assertEqual(owner("Shared_PolymorphHex_Impact.wav", "CS2_022", "Polymorph",
                               frozenset({"Shared_PolymorphHex_Impact.wav"})), "ok")
        self.assertEqual(owner("Mage_IceBlock_Impact_1.wav", "EX1_295", "Ice Block",
                               frozenset({"Mage_IceBlock_Impact_1.wav"})), "ok")
        self.assertEqual(owner("FX_FireballEvent01_BirthStart_01.wav", "CS2_029", "Fireball",
                               frozenset({"FX_FireballEvent01_BirthStart_01.wav"})), "ok")
        self.assertEqual(owner("Rogue_Vanish_Impact_1.wav", "X_1", "Hide", frozenset({"Rogue_Vanish_Impact_1.wav"})),
                         "info")
        self.assertEqual(owner("Coin_Underlay_Play.wav", "CFM_669", "Burgly Bully"), "info")
        self.assertEqual(owner("Pegasus_Stinger_Misc1.wav", "GVG_110", "Dr. Boom"), "info")

    def test_unrelated(self):
        self.assertEqual(owner("Pegasus_Stinger_Leeroy_Jenkins.wav", "GVG_110", "Dr. Boom"), "flag")
        self.assertEqual(owner("Murloc_Gurgle_Play.wav", "GVG_110", "Dr. Boom"), "flag")


class Lengths(unittest.TestCase):
    def test_rules(self):
        self.assertIsNone(cs.length_problem("hit", 1.2))
        self.assertIsNotNone(cs.length_problem("hit_3", 9.0))
        self.assertIsNotNone(cs.length_problem("music", 0.5))
        self.assertIsNotNone(cs.length_problem("music", 41.0))
        self.assertIsNone(cs.length_problem("music", 12.0))
        self.assertIsNotNone(cs.length_problem("aim", 0.1))
        self.assertIsNone(cs.length_problem("aim", 30.0))
        self.assertIsNotNone(cs.length_problem("play", 16.0, voice=True))
        self.assertIsNone(cs.length_problem("play", 9.0, voice=True))
        self.assertIsNone(cs.length_problem("play", None))


class Sources(unittest.TestCase):
    def test_plan_and_manifest(self):
        rows = {"OG_042": {"BASIC play": "VO_OG_133_Male_OldGod_Play_01.wav",
                           "BASIC play underlay": "Big_Underlay_Play.wav", "BASIC play stinger": "YShaarj_Play_Stinger.wav",
                           "BASIC death": "tt_lower_Death.wav"}}
        man = {"OG_042": {"hit": ["A_Impact.wav", "B_Impact.wav", "C_Impact.wav"], "hit_3": ["D_Impact.wav"],
                          "voice_trigger": ["VO_OG_042_Trigger_01.wav"], "aim": "Loop.wav"}}
        plan = cs.plan_sources([("OG_042", "MINION")], rows, [man])
        self.assertEqual(plan[("voice", "OG_042_play")], ["VO_OG_133_Male_OldGod_Play_01.wav"])
        self.assertEqual(plan[("set", "OG_042_play")], ["Big_Underlay_Play.wav"])
        self.assertEqual(plan[("set", "OG_042_music")], ["YShaarj_Play_Stinger.wav"])
        self.assertEqual(plan[("set", "OG_042_death")], ["Tt_lower_Death.wav"])  # (the wiki's capital first letter)
        self.assertEqual(plan[("set", "OG_042_hit")], ["A_Impact.wav"])
        self.assertEqual(plan[("set", "OG_042_hit_2")], ["B_Impact.wav"])
        self.assertEqual(plan[("set", "OG_042_hit_3")], ["D_Impact.wav"])
        self.assertEqual(plan[("voice", "OG_042_trigger")], ["VO_OG_042_Trigger_01.wav"])
        self.assertEqual(plan[("set", "OG_042_aim")], ["Loop.wav"])

    def test_vo_underlay_is_no_sound(self):
        row = {"BASIC play underlay": "VO_BRMA05_1_START_01.wav", "BASIC attack": "EX1_249_Baron_Geddon_Attack1.wav"}
        plan = snd.plan_card("VAN_EX1_249", row, "MINION")
        self.assertEqual(plan, [("set", "VAN_EX1_249_attack", "EX1_249_Baron_Geddon_Attack1.wav")])

    def test_ru_key(self):
        ru = {"vo_hero_08_well_played_57.wav": "x", "vo_og_042_play_01.wav": "y"}
        self.assertEqual(cs.ru_key("VO_OG_042_Play_01.wav", ru), "vo_og_042_play_01.wav")
        self.assertEqual(cs.ru_key("VO_HERO_08_WellPlayed_57.wav", ru), "vo_hero_08_well_played_57.wav")
        self.assertIsNone(cs.ru_key("VO_OG_133_Play_01.wav", ru))


if __name__ == "__main__":
    unittest.main()
