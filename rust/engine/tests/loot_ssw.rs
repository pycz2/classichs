//! Kobolds & Catacombs (packs/loot): the Shaman, Warlock and Warrior cards of scripts/loot_ssw.lua as on 2017-12-07
//! (build 22611). Needs python3 (skipped without it).

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

const DEMON: &str = "VAN_CS2_065"; // Voidwalker
const TOTEMS: [&str; 4] = ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"];

// --- Shaman ---------------------------------------------------------------------------------------------------------------

#[test]
fn crushing_hand_deals_8_and_overloads_3() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_060"]}, {"board": ["VAN_CS2_200"]});
    let e = t.nth(1, 0);
    t.play("LOOT_060", e);
    assert!(t.g.players[1].board.is_empty(), "Boulderfist Ogre 6/7 dies");
    assert_eq!(t.g.players[0].mana_lock_owed, 3);
}

#[test]
fn kobold_hermit_summons_the_chosen_totem_right_of_it() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_062"], "board": [WISP]}, {});
    t.play("LOOT_062", NONE);
    let mut o = t.options();
    o.sort();
    assert_eq!(o, TOTEMS.to_vec());
    t.pick_card("VAN_CS2_051");
    assert_eq!(t.cards(0), vec![WISP, "LOOT_062", "VAN_CS2_051"]);
}

#[test]
fn primal_talismans_gives_a_totem_deathrattle() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_344", FIREBALL], "board": [WISP, YETI]}, {});
    t.play("LOOT_344", NONE);
    let w = t.nth(0, 0);
    t.play(FIREBALL, w);
    let b = t.cards(0);
    assert_eq!(b.len(), 2, "{b:?}");
    assert!(TOTEMS.contains(&b[0].as_str()), "a totem where the Wisp was: {b:?}");
    assert_eq!(b[1], YETI);
}

#[test]
fn grumble_returns_your_other_minions_costing_1() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_358"], "board": [YETI, "VAN_CS2_200"]}, {"board": [WISP]});
    t.play("LOOT_358", NONE);
    assert_eq!(t.cards(0), vec!["LOOT_358"]);
    assert_eq!(t.cards(1), vec![WISP], "the enemy's stay");
    assert_eq!(t.hand(0), vec![YETI, "VAN_CS2_200"]);
    assert_eq!(t.cost(YETI), 1);
    assert_eq!(t.cost("VAN_CS2_200"), 1);
}

#[test]
fn healing_rain_heals_only_damaged_friends() {
    // 3 damage on the hero, 2 on the Yeti, none on the Wisp: 5 of the 12 are used, the rest is lost
    let mut t = scene!({"hero": "HERO_02", "damage": 3, "hand": ["LOOT_373"], "board": [WISP, {"card": YETI, "damage": 2}]}, {"board": [{"card": YETI, "damage": 2}]});
    t.play("LOOT_373", NONE);
    assert_eq!(t.hp(0), 30);
    assert_eq!(t.stats(t.nth(0, 1)), (4, 5));
    assert_eq!(t.stats(t.nth(1, 0)), (4, 3), "the enemy's not");
    let heals: Vec<_> = t.events().into_iter().filter(|e| e["type"] == "heal").collect();
    assert_eq!(heals.len(), 5, "one at a time: {heals:?}");
    // much damage: all 12
    let mut t = scene!({"hero": "HERO_02", "damage": 20, "hand": ["LOOT_373", "VAN_CS2_045"]}, {});
    t.play("LOOT_373", NONE);
    assert_eq!(t.hp(0), 22);
}

#[test]
fn unstable_evolution_repeats_this_turn() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_504"], "board": [WISP]}, {});
    let m = t.nth(0, 0);
    t.play("LOOT_504", m);
    let m = t.nth(0, 0);
    assert_eq!(rs().unwrap().card(&card_of(&t, m)).cost, 1, "{}", card_of(&t, m));
    assert_eq!(t.hand(0), vec!["LOOT_504t"]);
    t.play("LOOT_504t", m);
    let m = t.nth(0, 0);
    assert_eq!(rs().unwrap().card(&card_of(&t, m)).cost, 2, "{}", card_of(&t, m));
    assert_eq!(t.hand(0), vec!["LOOT_504t"], "the copy repeats too");
    t.end_turn();
    assert!(t.hand(0).is_empty(), "gone at the end of the turn");
    assert!(!t.events().iter().any(|e| e["type"] == "discard"), "removed, not discarded");
}

#[test]
fn the_runespear_discovers_a_spell_and_casts_it() {
    let mut t = scene!({"hero": "HERO_02", "weapon": "LOOT_506"}, {"board": [YETI]});
    let (h, e) = (t.hero(0), t.nth(1, 0));
    t.attack(h, e);
    let o = t.options();
    assert_eq!(o.len(), 3, "{o:?}");
    let rs = rs().unwrap();
    assert!(o.iter().all(|c| rs.card(c).kind == "SPELL"), "{o:?}");
    let c = t.pick_first();
    assert!(t.events().iter().any(|e| e["type"] == "cast" || e["type"] == "fizzle"), "{c} cast");
    // its last swing too
    let mut t = scene!({"hero": "HERO_02", "weapon": {"card": "LOOT_506", "durability": 1}}, {"board": [YETI]});
    let (h, e) = (t.hero(0), t.nth(1, 0));
    t.attack(h, e);
    assert!(t.g.players[0].weapon.is_none());
    assert_eq!(t.options().len(), 3);
    t.pick_first();
}

#[test]
fn windshear_stormcaller_needs_the_four_totems() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_518"], "board": TOTEMS}, {});
    t.play("LOOT_518", NONE);
    assert_eq!(t.cards(0)[5], "VAN_NEW1_010");
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_518"], "board": ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052"]}, {});
    t.play("LOOT_518", NONE);
    assert_eq!(t.cards(0).len(), 4);
}

// --- Warlock --------------------------------------------------------------------------------------------------------------

#[test]
fn kobold_librarian_and_vulgar_homunculus_hurt_your_hero() {
    let mut t = scene!({"hero": "HERO_07", "hand": ["LOOT_014", "LOOT_013"], "deck": [YETI]}, {});
    t.play("LOOT_014", NONE);
    assert_eq!(t.hand(0), vec!["LOOT_013", YETI]);
    assert_eq!(t.hp(0), 28);
    t.play("LOOT_013", NONE);
    assert_eq!(t.hp(0), 26);
}

#[test]
fn dark_pact_destroys_a_friend_and_heals_8() {
    let mut t = scene!({"hero": "HERO_07", "damage": 10, "hand": ["LOOT_017"], "board": [YETI]}, {"board": [WISP]});
    let m = t.nth(0, 0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == t.nth(1, 0)), "a friendly minion only");
    t.play("LOOT_017", m);
    assert!(t.g.players[0].board.is_empty());
    assert_eq!(t.hp(0), 28);
}

#[test]
fn hooked_reaver_at_15_health_or_less() {
    let mut t = scene!({"hero": "HERO_07", "damage": 15, "hand": ["LOOT_018"]}, {});
    t.play("LOOT_018", NONE);
    let m = t.nth(0, 0);
    assert_eq!(t.stats(m), (7, 7));
    assert!(t.g.e(m).has("TAUNT"));
    let mut t = scene!({"hero": "HERO_07", "damage": 14, "hand": ["LOOT_018"]}, {});
    t.play("LOOT_018", NONE);
    let m = t.nth(0, 0);
    assert_eq!(t.stats(m), (4, 4));
    assert!(!t.g.e(m).has("TAUNT"));
}

#[test]
fn possessed_lackey_recruits_a_demon() {
    let mut t = scene!({"hero": "HERO_07", "hand": [FIREBALL], "board": ["LOOT_306"], "deck": [WISP, DEMON, WISP]}, {});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!(t.cards(0), vec![DEMON]);
    assert_eq!(t.g.players[0].deck.len(), 2);
}

#[test]
fn voidlord_leaves_three_voidwalkers() {
    let mut t = scene!({"hero": "HERO_07", "hand": ["VAN_EX1_308"], "board": [WISP, "LOOT_368", YETI]}, {});
    let m = t.nth(0, 1);
    t.g.em(m).damage = 6;
    t.play("VAN_EX1_308", m); // Soulfire: 4
    assert_eq!(t.cards(0), vec![WISP, DEMON, DEMON, DEMON, YETI]);
}

#[test]
fn rin_and_her_seals_up_to_azari() {
    let mut t = scene!({"hero": "HERO_07", "hand": [FIREBALL], "board": [{"card": "LOOT_415", "damage": 3}]}, {"deck": [WISP, WISP, YETI]});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!(t.hand(0), vec!["LOOT_415t1"]);
    for n in 1..=5 {
        t.g.players[0].mana = 10;
        t.play(&format!("LOOT_415t{n}"), NONE);
        let f = t.on_board(0, &format!("LOOT_415t{n}t"));
        assert_eq!(t.stats(f), (n + 1, n + 1));
    }
    assert_eq!(t.hand(0), vec!["LOOT_415t6"]);
    t.g.players[0].mana = 10;
    t.play("LOOT_415t6", NONE);
    assert!(t.g.players[1].deck.is_empty(), "the opponent's deck is gone");
    assert!(t.g.players[1].hand.is_empty(), "not drawn");
}

#[test]
fn cataclysm_discards_before_the_deathrattles() {
    // Voidcaller's Deathrattle finds no Demon: the hand was discarded first
    let mut t = scene!({"hero": "HERO_07", "hand": ["LOOT_417", DEMON, WISP], "board": ["FP1_022"]}, {"board": [YETI]});
    t.play("LOOT_417", NONE);
    assert!(t.g.players[0].board.is_empty() && t.g.players[1].board.is_empty());
    assert!(t.hand(0).is_empty());
    assert_eq!(t.events().iter().filter(|e| e["type"] == "discard").count(), 2);
}

#[test]
fn skull_of_the_manari_summons_a_demon_before_the_draw() {
    let mut t = scene!({"hero": "HERO_07", "weapon": "LOOT_420", "hand": ["LOOT_013", WISP], "deck": ["VAN_CS2_059"]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.cards(0), vec!["LOOT_013"]);
    assert_eq!(t.hp(0), 30, "no Battlecry");
    assert_eq!(t.hand(0), vec![WISP, "VAN_CS2_059"], "the drawn Demon (Blood Imp) came after");
}

// --- Warrior --------------------------------------------------------------------------------------------------------------

#[test]
fn kobold_barbarian_attacks_a_random_enemy_at_the_start_of_your_turn() {
    let mut t = scene!({"board": ["LOOT_041"]}, {"board": [WISP]});
    let wisp = t.nth(1, 0);
    t.end_turn().end_turn();
    let hit = t.hp(1) == 26 || !t.g.players[1].board.contains(&wisp);
    assert!(hit, "it attacked");
    let b = t.on_board(0, "LOOT_041");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == b), "its attack of the turn (2017)");
}

#[test]
fn bladed_gauntlet_attack_is_your_armor_and_no_heroes() {
    let mut t = scene!({"armor": 5, "hand": ["LOOT_044", "VAN_EX1_606"]}, {"board": ["VAN_CS2_200"]});
    t.play("LOOT_044", NONE);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!(t.g.e(w).atk(), 5);
    t.play("VAN_EX1_606", NONE); // Shield Block: +5 Armor
    assert_eq!(t.g.e(w).atk(), 10);
    let h = t.hero(0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == h && int(a.get("defender")) == t.hero(1)));
    let ogre = t.nth(1, 0);
    t.attack(h, ogre);
    assert_eq!(t.armor(0), 4, "the Ogre's 6 came off the Armor");
    assert_eq!(t.g.e(w).atk(), 4);
}

#[test]
fn gemstudded_golem_attacks_only_with_5_armor() {
    let mut t = scene!({"armor": 4, "board": ["LOOT_365"]}, {});
    let m = t.nth(0, 0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == m));
    t.g.em(t.hero(0)).set_tag("ARMOR", 5i64);
    t.g.update_auras();
    let e = t.hero(1);
    t.attack(m, e);
    assert_eq!(t.hp(1), 25);
}

#[test]
fn reckless_flurry_spends_the_armor() {
    let mut t = scene!({"armor": 3, "hand": ["LOOT_364"], "board": [YETI]}, {"board": [YETI, "VAN_CS2_200"]});
    t.play("LOOT_364", NONE);
    assert_eq!(t.armor(0), 0);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 2));
    assert_eq!(t.stats(t.nth(1, 1)), (6, 4));
}

#[test]
fn drywhisker_armorer_2_armor_per_enemy_minion() {
    let mut t = scene!({"hand": ["LOOT_367"], "board": [WISP]}, {"board": [WISP, WISP, YETI]});
    t.play("LOOT_367", NONE);
    assert_eq!(t.armor(0), 6);
}

#[test]
fn gather_your_party_and_woecleaver_recruit() {
    let mut t = scene!({"hand": ["LOOT_370"], "deck": [FIREBALL, YETI, FIREBALL]}, {});
    t.play("LOOT_370", NONE);
    assert_eq!(t.cards(0), vec![YETI]);
    let mut t = scene!({"weapon": "LOOT_380", "deck": [FIREBALL, "VAN_CS2_200"]}, {});
    let (h, e) = (t.hero(0), t.hero(1));
    t.attack(h, e);
    assert_eq!(t.cards(0), vec!["VAN_CS2_200"]);
}

#[test]
fn geosculptor_yip_summons_a_minion_of_your_armor_cost() {
    let mut t = scene!({"armor": 3, "board": ["LOOT_519", WISP]}, {});
    t.end_turn();
    let b = t.cards(0);
    assert_eq!(b.len(), 3, "{b:?}");
    assert_eq!(rs().unwrap().card(&b[1]).cost, 3, "{b:?}: right of Yip");
    let mut t = scene!({"armor": 25, "board": ["LOOT_519"]}, {});
    t.end_turn();
    let b = t.cards(0);
    assert_eq!(rs().unwrap().card(&b[1]).cost, 10, "{b:?}");
}
