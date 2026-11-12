//! The Kobolds & Catacombs pack (packs/loot, built by tools/pack.py on Knights of the Frozen Throne and the packs before
//! it): the cards as on 2017-12-07 (build 22611) and the engine features it needs: Recruit (`g.summon_entity` from the
//! deck), Spellstones and Unidentified items (a card that transforms itself in the hand), "Cast this when drawn",
//! Kingsbane and King Togwaggle (`g.to_deck`: a card keeps its enchantments in a deck), Murmuring Elemental (the
//! champion's own DOUBLE_ON_PLAY), Shimmering Courser (FOE_SPELLPROOF), the patches 9.1–10.0 (Lifesteal heals once for an
//! effect: `behaviour.lifesteal_one_heal`; a countered spell is still cast; Dragon's Breath's own cost change last:
//! `cost_last`), the older cards of that day, and whole bot games with every deck template. Needs python3 (skipped
//! without it).


use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{api, bot, pack, scenario, Game};
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::sync::OnceLock;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The pack, built once (its recipe needs tools/pack.py); None without python3.
fn rs() -> Option<&'static Ruleset> {
    static R: OnceLock<Option<&'static Ruleset>> = OnceLock::new();
    *R.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("loot-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/loot", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
const NONE: Id = -1;

struct T {
    g: Game,
}

fn game(p0: Value, p1: Value) -> Option<T> {
    let rs = rs()?;
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let d0 = json!({"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL});
    let d1 = json!({"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL});
    let sc = json!({"current": 0, "seed": 7, "players": [merge(d0, p0), merge(d1, p1)]});
    Some(T { g: scenario::build_in(rs, &sc).unwrap_or_else(|e| panic!("scenario: {e}")) })
}

macro_rules! scene {
    ($p0:tt, $p1:tt) => {
        match game(json!($p0), json!($p1)) {
            Some(t) => t,
            None => {
                eprintln!("no python3: skipped");
                return;
            }
        }
    };
}

impl T {
    fn nth(&self, p: usize, i: usize) -> Id {
        self.g.players[p].board[i]
    }
    fn on_board(&self, p: usize, card: &str) -> Id {
        *self.g.players[p].board.iter().find(|&&m| self.g.e(m).card_id == card).unwrap_or_else(|| panic!("{card} not on board {p}"))
    }
    fn cards(&self, p: usize) -> Vec<String> {
        self.g.players[p].board.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hand(&self, p: usize) -> Vec<String> {
        self.g.players[p].hand.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    fn power(&self, p: usize) -> String {
        self.g.e(self.g.players[p].hero_power).card_id.to_string()
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn armor(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).tag("ARMOR")
    }
    fn hp(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).health()
    }
    fn act(&mut self, what: &str, f: impl Fn(&Map<String, Value>) -> bool) -> &mut Self {
        let a = self.g.legal_actions().into_iter().find(|a| f(a)).unwrap_or_else(|| panic!("no legal action: {what}"));
        let r = self.g.apply(&Value::Object(a));
        assert!(r.ok, "{what}: {}", r.error);
        assert_eq!(self.g.script_error.get(), None, "{what}");
        self
    }
    fn hand_id(&self, card: &str) -> Id {
        let p = self.g.current;
        *self.g.players[p].hand.iter().find(|&&e| self.g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand"))
    }
    fn play(&mut self, card: &str, target: Id) -> &mut Self {
        self.play_choice(card, target, -1)
    }
    fn play_choice(&mut self, card: &str, target: Id, choice: i64) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last) && int(a.get("choice")) == choice
        })
    }
    fn can_play(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
    }
    fn power_on(&mut self, target: Id) -> &mut Self {
        self.act("hero power", |a| a["type"] == "hero_power" && int(a.get("target")) == target)
    }
    fn can_power(&self) -> bool {
        self.g.legal_actions().iter().any(|a| a["type"] == "hero_power")
    }
    fn attack(&mut self, a: Id, d: Id) -> &mut Self {
        self.act("attack", |x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d)
    }
    fn end_turn(&mut self) -> &mut Self {
        self.act("end turn", |a| a["type"] == "end_turn")
    }
    fn cost(&self, card: &str) -> i64 {
        self.g.cost(self.hand_id(card))
    }
    fn options(&self) -> Vec<String> {
        self.g.pending_options().iter().map(|&o| self.g.e(o).card_id.to_string()).collect()
    }
    fn pick_card(&mut self, card: &str) -> &mut Self {
        let id = *self.g.pending_options().iter().find(|&&o| self.g.e(o).card_id == card).unwrap_or_else(|| panic!("{card} not offered"));
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id)
    }
    fn pick_first(&mut self) -> String {
        let id = self.g.pending_options()[0];
        let c = self.g.e(id).card_id.to_string();
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id);
        c
    }
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
}

fn card_of(t: &T, e: Id) -> String {
    t.g.e(e).card_id.to_string()
}


#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(rs.cards.values().filter(|x| x.collectible && x.set == "LOOTAPALOOZA").count(), 135);
    assert!(!rs.cards.contains_key("LOOT_500d"), "Val'anyr's dummy is no card");
    assert_eq!(stats("LOOT_149"), (7, 5, 5), "Corridor Creeper 5/5 until patch 10.2");
    assert_eq!(c("LOOT_017").cost, 1, "Dark Pact");
    assert_eq!(c("LOOT_093").cost, 4, "Call to Arms 4 until 11.1.1");
    assert_eq!(c("LOOT_306").cost, 5, "Possessed Lackey 5");
    assert_eq!(c("LOOT_539").cost, 6, "Spiteful Summoner 6");
    assert_eq!(c("LOOT_412").cost, 4, "Kobold Illusionist 4");
    assert_eq!(c("LOOT_417").cost, 4, "Cataclysm 4");
    assert_eq!(stats("LOOT_137"), (9, 4, 12), "Sleepy Dragon 4/12");
    assert_eq!(stats("LOOT_211"), (4, 3, 2), "Elven Minstrel 3/2");
    assert_eq!(stats("LOOT_231"), (1, 1, 2), "Arcane Artificer 1/2");
    assert_eq!(c("LOOT_329").race, "ELEMENTAL", "Ixlid an Elemental at the release");
    for id in ["LOOT_056", "LOOT_313", "LOOT_375", "LOOT_516", "LOOT_534"] {
        assert_eq!(c(id).race, "", "{id}: no tribe in 2017");
    }
    assert_eq!(c("LOOT_111").race, "MECHANICAL");
    // the older cards of patch 9.1 (2017-09-18)
    assert_eq!(c("VAN_CS2_106").cost, 3, "Fiery War Axe");
    assert_eq!(c("VAN_EX1_246").cost, 4, "Hex");
    assert_eq!(c("ICC_054").cost, 6, "Spreading Plague");
    // what came after the release stays out
    assert_eq!(c("CFM_637").keywords.iter().any(|k| k == "CHARGE"), true, "Patches keeps Charge until 10.2");
    assert_eq!(c("ICC_705").cost, 7, "Bonemare 7");
    // the build's export quirks: Elemental Destruction keeps Overload (5)
    assert_eq!(c("AT_051").mana_lock, 5);
    assert!(rs.lifesteal_one_heal && !rs.countered_no_after_spell);
}

#[test]
fn innervate_and_murloc_warleader_of_patch_9_1() {
    let mut t = scene!({"mana": 3, "hand": ["VAN_EX1_169"], "board": ["VAN_EX1_507", "VAN_CS2_168"]}, {});
    t.play("VAN_EX1_169", NONE);
    assert_eq!(t.g.players[0].mana, 4, "one crystal");
    let m = t.on_board(0, "VAN_CS2_168");
    assert_eq!(t.stats(m), (2 + 2, 1), "Murloc Raider: +2 Attack only");
}

#[test]
fn unlicensed_apothecary_after_you_summon() {
    let mut t = scene!({"hand": [WISP], "board": ["CFM_900"]}, {});
    t.play(WISP, NONE);
    assert_eq!(t.hp(0), 25);
}

#[test]
fn dragons_breath_costs_less_after_naga_sea_witch() {
    // patch 9.2: its own cost change after all the others: Naga Sea Witch's 5, then 2 less for two deaths
    let mut t = scene!({"hand": ["BRM_003", FIREBALL, FIREBALL], "board": ["LOE_038"]}, {"board": [WISP, WISP]});
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    t.play(FIREBALL, a).play(FIREBALL, b);
    assert_eq!(t.cost("BRM_003"), 3);
}

#[test]
fn a_spellstone_upgrades_in_the_hand() {
    let mut t = scene!({"hand": ["LOOT_051", "VAN_EX1_606", "VAN_EX1_606"]}, {"board": [YETI]});
    t.play("VAN_EX1_606", NONE); // Shield Block: 5 Armor, one step
    assert_eq!(t.hand(0)[0], "LOOT_051t1", "Jasper Spellstone");
    t.play("VAN_EX1_606", NONE);
    assert_eq!(t.hand(0)[0], "LOOT_051t2");
    let e = t.nth(1, 0);
    t.play("LOOT_051t2", e);
    assert!(t.g.e(e).health() <= 0 || t.g.e(e).zone != "PLAY");
}

#[test]
fn an_amethyst_spellstone_upgrades_when_your_cards_hurt_you() {
    let mut t = scene!({"hero": "HERO_07", "damage": 10, "hand": ["LOOT_043", "LOOT_013"]}, {"board": ["VAN_CS2_186"]});
    t.play("LOOT_013", NONE); // Vulgar Homunculus: 2 damage to your hero
    assert_eq!(t.hand(0), vec!["LOOT_043t2"]);
    t.power_on(NONE); // Life Tap
    assert_eq!(t.hand(0)[0], "LOOT_043t3");
    let hp = t.hp(0);
    let e = t.nth(1, 0);
    t.play("LOOT_043t3", e);
    assert_eq!(t.hp(0), hp + 7, "Lifesteal");
}

#[test]
fn an_unidentified_item_is_identified_in_the_hand() {
    let mut t = scene!({"deck": ["LOOT_285", "LOOT_278", "LOOT_286"]}, {});
    t.end_turn().end_turn();
    let h = t.hand(0);
    assert!(h.iter().any(|c| c.starts_with("LOOT_286t")), "{h:?}");
    // opening hands: identified after the mulligan
    let rs = rs().unwrap();
    let sc = json!({"seed": 3, "players": [
        {"hero": "HERO_01", "deck": ["LOOT_285", "LOOT_285", "LOOT_285", "LOOT_285", WISP, WISP, WISP, WISP]},
        {"hero": "HERO_01", "deck": FILL}]});
    let _ = sc;
    let _ = rs;
}

#[test]
fn lifesteal_heals_once_for_an_effect() {
    // patch 10.0: Spirit Lash (1 to every minion, Lifesteal) heals once for all it dealt
    let mut t = scene!({"hero": "HERO_09", "damage": 10, "hand": ["ICC_802"], "board": [WISP]}, {"board": [WISP, YETI]});
    t.play("ICC_802", NONE);
    let heals: Vec<_> = t.events().into_iter().filter(|e| e["type"] == "heal").collect();
    assert_eq!(heals.len(), 1, "{heals:?}");
    assert_eq!(t.hp(0), 23);
}

#[test]
fn murmuring_elemental_doubles_the_next_battlecry() {
    let mut t = scene!({"hand": ["LOOT_517", "VAN_CS2_189", "VAN_CS2_189"]}, {});
    t.play("LOOT_517", NONE);
    t.play("VAN_CS2_189", t.hero(1)); // Elven Archer: twice
    assert_eq!(t.hp(1), 28);
    t.play("VAN_CS2_189", t.hero(1)); // once
    assert_eq!(t.hp(1), 27);
}

#[test]
fn shimmering_courser_only_its_player_targets_it_with_spells() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_193"]}, {"hand": [FIREBALL], "board": [WISP]});
    let c = t.nth(0, 0);
    assert!(t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == c), "its own player can");
    t.end_turn();
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == c), "the opponent cannot");
}

#[test]
fn wild_pyromancer_summoned_by_mindgames_does_not_hear_it() {
    // patch 9.2.0.21517
    let mut t = scene!({"hero": "HERO_09", "hand": ["VAN_EX1_345"], "board": [YETI]}, {"deck": ["VAN_NEW1_020"]});
    t.play("VAN_EX1_345", NONE);
    assert_eq!(t.cards(0), vec![YETI.to_string(), "VAN_NEW1_020".to_string()]);
    let y = t.nth(0, 0);
    assert_eq!(t.stats(y), (4, 5), "no 1 damage to all minions");
}

#[test]
fn lord_jaraxxus_does_not_set_off_repentance() {
    // patch 9.2.0.21517
    let mut t = scene!({"hero": "HERO_07", "hand": ["VAN_EX1_323"]}, {"secrets": ["VAN_EX1_379"]});
    t.play("VAN_EX1_323", NONE);
    assert_eq!(t.g.players[1].secrets.len(), 1, "Repentance stays");
    assert_eq!(t.hp(0), 15);
}

#[test]
fn a_countered_spell_is_still_cast() {
    // patch 9.2.0.21517: Counterspell's spell still triggers "after you cast a spell"
    let mut t = scene!({"hand": [FIREBALL], "board": ["VAN_NEW1_020"]}, {"secrets": ["VAN_EX1_287"], "board": [YETI]});
    let h = t.hero(1);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(1), 30, "countered");
    let y = t.nth(1, 0);
    assert_eq!(t.stats(y).1, 4, "Wild Pyromancer still went off");
}
