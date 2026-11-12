//! Kobolds & Catacombs (packs/loot): the neutral cards (scripts/loot_neutral.lua) as on 2017-12-07 (build 22611).
//! Needs python3 (skipped without it).

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

const FLAMESTRIKE: &str = "VAN_CS2_032";
const AXE: &str = "VAN_CS2_106";
const EXECUTE: &str = "VAN_CS2_108";
const RAPTOR: &str = "VAN_CS2_172";
const CROC: &str = "VAN_CS2_120";
const RAGNAROS: &str = "VAN_EX1_298";
const AZURE: &str = "VAN_EX1_284";

impl T {
    fn deck(&self, p: usize) -> Vec<String> {
        self.g.players[p].deck.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn board_ids(&self, p: usize) -> Vec<Id> {
        self.g.players[p].board.clone()
    }
}

#[test]
fn the_darkness_sleeps_until_its_three_candles_are_drawn() {
    let mut t = scene!({"hand": ["LOOT_526"]}, {"deck": []});
    t.play("LOOT_526", NONE);
    let d = t.on_board(0, "LOOT_526");
    assert!(!t.g.awake(d), "it starts Dormant");
    assert_eq!(t.deck(1), vec!["LOOT_526t"; 3]);
    // the opponent draws a candle: it is cast (snuff, draw), the next one too… the third wakes The Darkness
    t.end_turn();
    assert!(t.g.awake(d), "awake after three candles");
    assert!(t.deck(1).is_empty() && t.hand(1).is_empty(), "{:?} {:?}", t.deck(1), t.hand(1));
    assert_eq!(t.stats(d), (20, 20));
}

#[test]
fn a_darkness_summoned_without_its_battlecry_sleeps_for_good() {
    // Guild Recruiter recruits it (Cost 4): Dormant, no candles
    let mut t = scene!({"hand": ["LOOT_375"], "deck": ["LOOT_526"]}, {});
    t.play("LOOT_375", NONE);
    let d = t.on_board(0, "LOOT_526");
    assert!(!t.g.awake(d));
    assert!(!t.deck(1).iter().any(|c| c == "LOOT_526t"));
}

#[test]
fn a_candle_of_ones_own_snuffs_nothing_but_draws() {
    // a Darkness candle cast for the Darkness's own player (Psionic Probe's copy) only draws
    let mut t = scene!({"hand": ["LOOT_526", "LOOT_526t"]}, {});
    t.play("LOOT_526", NONE);
    let d = t.on_board(0, "LOOT_526");
    let n = t.hand(0).len();
    t.play("LOOT_526t", NONE);
    assert!(!t.g.awake(d));
    assert_eq!(t.hand(0).len(), n, "played one, drew one");
}

#[test]
fn corridor_creeper_costs_less_for_each_death_while_in_hand() {
    let mut t = scene!({"hand": ["LOOT_149", FIREBALL, FIREBALL]}, {"board": [WISP, WISP]});
    assert_eq!(t.cost("LOOT_149"), 7);
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    t.play(FIREBALL, a).play(FIREBALL, b);
    assert_eq!(t.cost("LOOT_149"), 5);
}

#[test]
fn arcane_tyrant_costs_nothing_after_a_big_spell() {
    let mut t = scene!({"hand": ["LOOT_130", FLAMESTRIKE, "VAN_CS2_023"]}, {"board": [WISP]});
    t.play("VAN_CS2_023", NONE);
    assert_eq!(t.cost("LOOT_130"), 5, "a 3-Cost spell does not count");
    t.play(FLAMESTRIKE, NONE);
    assert_eq!(t.cost("LOOT_130"), 0);
    t.end_turn().end_turn();
    assert_eq!(t.cost("LOOT_130"), 5, "this turn only");
}

#[test]
fn carnivorous_cube_eats_a_minion_and_gives_two_back() {
    let mut t = scene!({"hand": ["LOOT_161"], "board": [YETI]}, {"hand": [FIREBALL]});
    let y = t.nth(0, 0);
    t.play("LOOT_161", y);
    assert_eq!(t.cards(0), vec!["LOOT_161"]);
    let c = t.nth(0, 0);
    t.end_turn();
    t.play(FIREBALL, c);
    assert_eq!(t.cards(0), vec![YETI, YETI]);
    for m in t.board_ids(0) {
        assert_eq!(t.stats(m), (4, 5), "plain copies");
    }
}

#[test]
fn marins_chest_gives_marins_player_a_treasure() {
    let mut t = scene!({"hand": ["LOOT_357"]}, {});
    t.play("LOOT_357", NONE);
    assert_eq!(t.cards(1), vec!["LOOT_357l"]);
    let mut t = scene!({"hand": [FIREBALL, FIREBALL]}, {"board": ["LOOT_357l"]});
    let c = t.nth(1, 0);
    t.play(FIREBALL, c).play(FIREBALL, c);
    let h = t.hand(0);
    assert_eq!(h.len(), 1);
    assert!(["LOOT_998h", "LOOT_998j", "LOOT_998k", "LOOT_998l"].contains(&h[0].as_str()), "{h:?}");
}

#[test]
fn the_treasures() {
    // Tolin's Goblet: draw a card, fill the hand with copies of it
    let mut t = scene!({"hand": ["LOOT_998h"], "deck": [YETI]}, {});
    t.play("LOOT_998h", NONE);
    assert_eq!(t.hand(0), vec![YETI; 10]);
    // Wondrous Wand: three cards that cost (0)
    let mut t = scene!({"hand": ["LOOT_998l"], "deck": [YETI, RAGNAROS, FIREBALL]}, {});
    t.play("LOOT_998l", NONE);
    assert_eq!(t.hand(0).len(), 3);
    for c in [YETI, RAGNAROS, FIREBALL] {
        assert_eq!(t.cost(c), 0, "{c}");
    }
    // Golden Kobold: the rest of the hand becomes Legendary minions
    let mut t = scene!({"hand": ["LOOT_998k", WISP, FIREBALL]}, {});
    t.play("LOOT_998k", NONE);
    let rs = rs().unwrap();
    let h = t.hand(0);
    assert_eq!(h.len(), 2);
    for c in &h {
        assert!(rs.card(c).rarity == "LEGENDARY" && rs.card(c).kind == "MINION", "{c}");
    }
    // Zarog's Crown: Discover a Legendary minion, two of it
    let mut t = scene!({"hand": ["LOOT_998j"]}, {});
    t.play("LOOT_998j", NONE);
    let c = t.pick_first();
    assert_eq!(rs.card(&c).rarity, "LEGENDARY");
    assert_eq!(t.cards(0), vec![c.clone(), c]);
}

#[test]
fn king_togwaggle_swaps_the_decks_and_gives_a_ransom() {
    let mut t = scene!({"hand": ["LOOT_541"], "deck": [WISP, WISP]}, {"deck": [YETI, YETI, YETI]});
    t.play("LOOT_541", NONE);
    assert_eq!(t.deck(0), vec![YETI; 3]);
    assert_eq!(t.deck(1), vec![WISP; 2]);
    assert_eq!(t.hand(1), vec!["LOOT_541t"]);
    t.end_turn(); // the opponent draws a Wisp and swaps back
    t.play("LOOT_541t", NONE);
    assert_eq!(t.deck(1), vec![YETI; 3]);
    assert_eq!(t.deck(0), vec![WISP]);
}

#[test]
fn grand_archivist_casts_a_spell_of_the_deck() {
    // Execute has no target (no damaged enemy): it stays; the Fireball is cast from the deck
    let mut t = scene!({"board": ["LOOT_414"], "deck": [EXECUTE, FIREBALL, WISP]}, {"deck": FILL});
    let hp = t.hp(1) + t.hp(0) + t.g.e(t.nth(0, 0)).health();
    t.end_turn();
    let d = t.deck(0);
    assert!(d.contains(&EXECUTE.to_string()) && !d.contains(&FIREBALL.to_string()), "{d:?}");
    let after = t.hp(1) + t.hp(0) + t.g.players[0].board.first().map_or(0, |&m| t.g.e(m).health());
    assert!(after <= hp - 6 || t.g.players[0].board.is_empty(), "6 damage somewhere");
}

#[test]
fn spiteful_summoner_reveals_a_spell_and_summons_a_minion_of_its_cost() {
    let mut t = scene!({"hand": ["LOOT_539"], "deck": [FIREBALL, WISP]}, {});
    t.play("LOOT_539", NONE);
    let rs = rs().unwrap();
    assert_eq!(t.cards(0).len(), 2);
    assert_eq!(rs.card(&t.cards(0)[1]).cost, 4);
    assert!(t.events().iter().any(|e| e["type"] == "reveal" && e["card"] == FIREBALL));
    assert_eq!(t.deck(0).len(), 2, "the spell stays");
}

#[test]
fn kobold_monk_shields_its_champion_from_spells() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_382"]}, {"hand": [FIREBALL]});
    let h0 = t.hero(0);
    let targets_h0 = |t: &T| t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == h0);
    assert!(!targets_h0(&t), "not even its own player");
    t.end_turn();
    assert!(!targets_h0(&t));
}

#[test]
fn rummaging_kobold_returns_a_destroyed_weapon() {
    let mut t = scene!({"weapon": "VAN_CS2_106", "hand": ["LOOT_389"]}, {"hand": ["LOOT_122"]});
    t.end_turn();
    t.play("LOOT_122", NONE); // Corrosive Sludge
    assert!(t.g.players[0].weapon.is_none());
    t.end_turn();
    t.play("LOOT_389", NONE);
    assert!(t.hand(0).contains(&AXE.to_string()), "{:?}", t.hand(0));
}

#[test]
fn void_ripper_swaps_attack_and_health() {
    let mut t = scene!({"hand": ["LOOT_529"], "board": [YETI, "LOOT_117"]}, {"board": [RAPTOR]});
    t.play("LOOT_529", NONE);
    assert_eq!(t.cards(0), vec![YETI, "LOOT_529"], "the 0/2 Wax Elemental dies");
    assert_eq!(t.stats(t.nth(0, 0)), (5, 4));
    assert_eq!(t.stats(t.nth(1, 0)), (2, 3));
    assert_eq!(t.stats(t.nth(0, 1)), (3, 3), "not itself");
}

#[test]
fn master_oakheart_recruits_a_1_2_and_3_attack_minion() {
    let mut t = scene!({"hand": ["LOOT_521"], "deck": [YETI, RAPTOR, CROC, WISP, YETI]}, {});
    t.play("LOOT_521", NONE);
    assert_eq!(t.cards(0), vec!["LOOT_521", WISP, CROC, RAPTOR]);
    assert_eq!(t.deck(0), vec![YETI, YETI]);
}

#[test]
fn recruits_on_death_and_at_end_of_turn() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_184", "LOOT_540"], "deck": [RAGNAROS, YETI, "LOOT_137"]}, {});
    let v = t.nth(0, 0);
    t.play(FIREBALL, v);
    assert!(t.cards(0).contains(&RAGNAROS.to_string()), "Silver Vanguard: an 8-Cost minion");
    t.end_turn();
    assert!(t.cards(0).contains(&"LOOT_137".to_string()), "Dragonhatcher: a Dragon");
}

#[test]
fn toothy_chest_has_4_attack_from_its_turn_start() {
    let mut t = scene!({"board": ["LOOT_134"]}, {});
    let c = t.nth(0, 0);
    t.end_turn();
    assert_eq!(t.stats(c).0, 0);
    t.end_turn();
    assert_eq!(t.stats(c).0, 4);
}

#[test]
fn feral_gibberer_copies_itself_after_hitting_a_hero() {
    let mut t = scene!({"board": ["LOOT_218"]}, {});
    let (m, h) = (t.nth(0, 0), t.hero(1));
    t.attack(m, h);
    assert_eq!(t.hand(0), vec!["LOOT_218"]);
}

#[test]
fn small_battlecries() {
    // Kobold Apprentice: 3 damage split among the enemies
    let mut t = scene!({"hand": ["LOOT_347"]}, {"board": [YETI]});
    t.play("LOOT_347", NONE);
    let y = t.nth(1, 0);
    assert_eq!(30 - t.hp(1) + t.g.e(y).damage, 3);
    // Lone Champion alone: Taunt and Divine Shield; not alone: nothing
    let mut t = scene!({"hand": ["LOOT_124", "LOOT_124"]}, {});
    t.play("LOOT_124", NONE).play("LOOT_124", NONE);
    let (a, b) = (t.nth(0, 0), t.nth(0, 1));
    assert!(t.g.e(a).has("TAUNT") && t.g.e(a).has("DIVINE_SHIELD"));
    assert!(!t.g.e(b).has("TAUNT"));
    // Scorp-o-matic only on a minion with 1 or less Attack; Dragonslayer only on a Dragon
    let mut t = scene!({"hand": ["LOOT_111", "LOOT_132"]}, {"board": [WISP, YETI, AZURE]});
    let (w, y, d) = (t.nth(1, 0), t.nth(1, 1), t.nth(1, 2));
    let targets = |t: &T, card: &str| {
        let e = t.hand_id(card);
        t.g.legal_actions().iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).map(|a| int(a.get("target"))).collect::<Vec<_>>()
    };
    let s = targets(&t, "LOOT_111");
    assert!(s.contains(&w) && !s.contains(&y));
    let s = targets(&t, "LOOT_132");
    assert!(s.contains(&d) && !s.contains(&y));
    t.play("LOOT_111", w).play("LOOT_132", d);
    assert_eq!(t.cards(1), vec![YETI]);
    // Ebon Dragonsmith: a weapon in the hand costs (2) less
    let mut t = scene!({"hand": ["LOOT_118", AXE]}, {});
    t.play("LOOT_118", NONE);
    assert_eq!(t.cost(AXE), 1);
    // Hoarding Dragon: two Coins for the opponent
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_144"]}, {});
    let d = t.nth(0, 0);
    t.play(FIREBALL, d);
    assert_eq!(t.hand(1), vec!["GAME_005", "GAME_005"]);
    // Violet Wurm: seven Grubs
    let mut t = scene!({"hand": [FIREBALL, FIREBALL], "board": ["LOOT_153"]}, {});
    let d = t.nth(0, 0);
    t.play(FIREBALL, d).play(FIREBALL, d);
    assert_eq!(t.cards(0), vec!["LOOT_153t1"; 7]);
    // Gravelsnout Knight and Hungry Ettin: a random 1- / 2-Cost minion for the opponent
    let mut t = scene!({"hand": ["LOOT_154", "LOOT_383"]}, {});
    t.play("LOOT_154", NONE).play("LOOT_383", NONE);
    let rs = rs().unwrap();
    let c: Vec<i64> = t.cards(1).iter().map(|c| rs.card(c).cost).collect();
    assert_eq!(c, vec![1, 2]);
    // Furbolg Mossbinder and Zola
    let mut t = scene!({"hand": ["LOOT_150", "LOOT_516"], "board": [WISP, YETI]}, {});
    let (w, y) = (t.nth(0, 0), t.nth(0, 1));
    t.play("LOOT_150", w).play("LOOT_516", y);
    assert_eq!(t.cards(0)[0], "LOOT_150t1");
    assert_eq!(t.hand(0), vec![YETI]);
}

#[test]
fn end_of_turn_summons() {
    let mut t = scene!({"board": ["LOOT_131", "LOOT_394"]}, {});
    t.end_turn();
    let rs = rs().unwrap();
    let c = t.cards(0);
    assert_eq!(c.len(), 4, "{c:?}");
    assert!(c.contains(&"LOOT_131t1".to_string()));
    assert!(c.iter().any(|x| x != "LOOT_131t1" && x != "LOOT_131" && x != "LOOT_394" && rs.card(x).cost == 1));
}
