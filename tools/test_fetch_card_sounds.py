"""Tests of tools/fetch_card_sounds.py (offline, wiki file names as fixtures):
python3 -m unittest tools/test_fetch_card_sounds.py (from the repo root)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_card_sounds as fcs  # noqa: E402

OTHERS = {"deathspeaker blackthorn", "deathwing", "deathwing dragonlord", "deathwing mad aspect", "ooze",
          "thickhide kodo", "thick hide", "arcane missiles", "darkbomb", "biteweed", "deathspeaker"}
JOINED = {o.replace(" ", "") for o in OTHERS}


class Words(unittest.TestCase):
    def test_split(self):
        self.assertEqual(fcs.words("Mage_ArcaneMissiles_Impact_1"), ["mage", "arcane", "missiles", "impact", "1"])
        self.assertEqual(fcs.words("Y'Shaarj, Rage Unbound"), ["y", "shaarj", "rage", "unbound"])
        self.assertEqual(fcs.words("SFX_GVG_007_EnterPlay"), ["sfx", "gvg", "007", "enter", "play"])

    def test_role_of(self):
        self.assertEqual(fcs.role_of(["impact", "1"]), "hit")
        self.assertEqual(fcs.role_of(["idle", "sound"]), "aim")
        self.assertEqual(fcs.role_of(["battlecry", "impact"]), "hit")  # an impact is an impact
        self.assertEqual(fcs.role_of(["sound"]), "")


class Match(unittest.TestCase):
    def m(self, f, name, cid):
        return fcs.match(f, name, cid, others=JOINED, keys=fcs.card_keys(name, sorted(OTHERS)))

    def test_spell_roles(self):
        self.assertEqual(self.m("Mage_ArcaneMissiles_Impact_1.wav", "Arcane Missiles", "VAN_EX1_277"), "hit")
        self.assertEqual(self.m("Warlock_Darkbomb_Missile_Sound_01.wav", "Darkbomb", "GVG_015"), "missile")
        self.assertEqual(self.m("Darkbomb_Idle_Sound_01.wav", "Darkbomb", "GVG_015"), "aim")
        self.assertEqual(self.m("FX_FireballEvent01_BirthStart_01.wav", "Fireball", "CS2_029"), "")  # (part of a word)
        self.assertEqual(self.m("Shared_Fire_Cast_1.wav", "Fireball", "CS2_029"), "")

    def test_not_the_cards(self):
        self.assertEqual(self.m("Khadgar_Fireblast_Cast_Sound_01.wav", "Fireblast", "CS2_034"), "")  # a skin's
        self.assertEqual(self.m("Fireblast_Impact_Blue.wav", "Fireblast", "CS2_034"), "")
        self.assertEqual(self.m("Charge_Summon.wav", "Charge", "CS2_103"), "")  # the keyword's
        self.assertEqual(self.m("SFX_EX1_025t_EnterPlay.wav", "Dragonling Mechanic", "EX1_025"), "")  # its token's
        self.assertEqual(self.m("DruidOfTheClaw_OG_044a_Play.wav", "Druid of the Claw", "EX1_165"), "")  # another id
        self.assertEqual(self.m("Death_Speaker_Blackthorn_Play_01.wav", "Deathspeaker", "ICC_467"), "")
        self.assertEqual(self.m("Thickhide_Kodo_Play_01.wav", "Thick Hide", "EX1_155b"), "")
        self.assertEqual(self.m("VO_EX1_559_Trigger_02.wav", "Archmage Antonidas", "EX1_559"), "")  # a voice line
        self.assertEqual(self.m("Voidwalker_Underlay_Play.wav", "Voidwalker", "CS2_065"), "")  # a shared underlay

    def test_effects_and_ids(self):
        self.assertEqual(self.m("AcidicSwampOoze_AcidGlobThrow_Cast_1.wav", "Acidic Swamp Ooze", "EX1_066"), "*play")
        self.assertEqual(self.m("UNG_063_SproutingSporling_Play.wav", "Biteweed", "UNG_063"), "+play")  # an old name
        self.assertEqual(self.m("FaceCollector_SpawnToHand_Sound.wav", "Face Collector", "GIL_677"), "*play")

    def test_short_name(self):
        keys = fcs.card_keys("Deathwing, Dragonlord", sorted(OTHERS))
        self.assertNotIn("deathwing", keys)
        self.assertIn("deathwingdragonlord", keys)
        self.assertIn("ixlid", fcs.card_keys("Ixlid, Fungal Lord", sorted(OTHERS)))


class Plan(unittest.TestCase):
    FILES = ["Mage_ArcaneMissiles_Impact_2.wav", "Mage_ArcaneMissiles_Impact_1.wav", "Mage_ArcaneMissiles_Impact_3.wav",
             "ArcaneMissile_07_Impact_01.wav", "LeperGnome_DeathRattle_Cast_1.wav", "LeperGnome_DeathRattle_Target_1.wav",
             "Crush_CustomDeath_Sound_01.wav", "Druid_Shapeshift_Cast_1.wav", "Onyxia_CustomSummon_Cast.wav",
             "Onyxia_CustomSummon_Impact.wav", "GVG_093_TargetDummy_Attack.wav", "Mage_IceBarrier_Impact_1.wav",
             "Mage_ArcaneExplosion_AE_1.wav"]
    CARDS = [("VAN_EX1_277", "SPELL", "Arcane Missiles"), ("VAN_EX1_029", "MINION", "Leper Gnome"),
             ("GVG_052", "SPELL", "Crush"), ("VAN_HERO_06bp", "HERO_POWER", "Shapeshift"),
             ("VAN_EX1_562", "MINION", "Onyxia"), ("GVG_093", "MINION", "Target Dummy"),
             ("VAN_EX1_289", "SPELL", "Ice Barrier"), ("VAN_CS2_025", "SPELL", "Arcane Explosion")]

    def test_plan(self):
        m = fcs.plan(self.CARDS, self.FILES, have={"VAN_EX1_562_play"}, others=OTHERS)
        # the hand-picked impact's family, in order (fetch_original_sounds.SPELLS: Mage_ArcaneMissiles_Impact_1)
        self.assertEqual(m["VAN_EX1_277"], {"hit": ["Mage_ArcaneMissiles_Impact_1.wav", "Mage_ArcaneMissiles_Impact_2.wav",
                                                    "Mage_ArcaneMissiles_Impact_3.wav"]})
        self.assertEqual(m["VAN_EX1_029"], {"trigger": ["LeperGnome_DeathRattle_Cast_1.wav"],
                                            "hit": ["LeperGnome_DeathRattle_Target_1.wav"]})
        self.assertEqual(m["GVG_052"], {"hit": ["Crush_CustomDeath_Sound_01.wav"]})  # a spell's "death" is its impact
        self.assertEqual(m["VAN_HERO_06bp"], {"play": ["Druid_Shapeshift_Cast_1.wav"]})
        self.assertNotIn("VAN_EX1_562", m)  # its play exists; its entrance's landing is no impact
        self.assertEqual(m["GVG_093"], {"attack": ["GVG_093_TargetDummy_Attack.wav"]})  # "Target" is its name
        self.assertEqual(m["VAN_EX1_289"], {"reveal": ["Mage_IceBarrier_Impact_1.wav"]})  # a Secret: as revealed
        self.assertNotIn("VAN_CS2_025", m)  # its hand-picked cast is the whole effect: no impact again

    def test_set_names(self):
        self.assertEqual(fcs.set_names("X", {"hit": ["a.wav", "b.wav"], "aim": ["c.wav"]}),
                         [("X_hit", "a.wav"), ("X_hit_2", "b.wav"), ("X_aim", "c.wav")])

    def test_inherited(self):
        rows = {"CFM_712_t01": {"BASIC play": "JadeGolem_Tier1_Play.wav"}, "CFM_712_t02": {},
                "CFM_712_t04": {"BASIC play": "JadeGolem_Tier2_Play.wav", "BASIC death": "JadeGolem_Tier2_Death.wav"},
                "CFM_712_t05": {}, "X_1": {}}
        self.assertEqual(fcs.inherited(list(rows), rows),
                         {"CFM_712_t02": {"play": ["JadeGolem_Tier1_Play.wav"]},
                          "CFM_712_t05": {"play": ["JadeGolem_Tier2_Play.wav"], "death": ["JadeGolem_Tier2_Death.wav"]}})

    def test_vo_triggers(self):
        files = ["VO_GVG_007_Trigger_04.wav", "VO_GVG_007_Play_01.wav", "VO_GVG_0071_Trigger_01.wav",
                 "VO_LOOT_108_Male_Weapon_Trigger_02.wav", "VO_LOOT_108_Male_Weapon_Trigger_01.wav"]
        self.assertEqual(fcs.vo_triggers(["GVG_007", "LOOT_108", "GVG_008"], files),
                         {"GVG_007": "VO_GVG_007_Trigger_04.wav", "LOOT_108": "VO_LOOT_108_Male_Weapon_Trigger_01.wav"})


if __name__ == "__main__":
    unittest.main()
